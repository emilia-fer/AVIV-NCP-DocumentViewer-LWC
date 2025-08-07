/* ====================================================================== *
 *  FileSyncBatch.cls
 *  ------------------------------------------------------------------   *
 *  • Picks the set of ContentVersion records that must be synchronised   *
 *    with S3 and delegates each one to FileSyncWorker.                  *
 *  • Retries *failed* uploads automatically (max 3 attempts).           *
 *  • Sends one e-mail summary (plain-text) after every run.             *
 *                                                                        *
 *  Governor-friendly design                                              *
 *  ----------------------                                                *
 *  – Uses Database.Stateful to keep counters & failed-ID set             *
 *  – Uses try/catch inside execute() so one bad file never aborts        *
 *  – Retry batch is scoped to only the failed Ids → fewer API calls      *
 * ====================================================================== */

global with sharing class FileSyncBatch
    implements Database.Batchable<SObject>,
               Database.Stateful,
               Database.AllowsCallouts
{
    /* ------------------------------------------------------------------ *
     *  Constructors                                                       *
     * ------------------------------------------------------------------ */

    /** normal nightly run – “sync all files touched since <date>” */
    public FileSyncBatch(DateTime sinceWhen){
        this.sinceDate = sinceWhen;
        this.attempt   = 1;
    }

    /** retry run – only for specific CV Ids that failed before    */
    public FileSyncBatch(Set<Id> retryIds, Integer attemptNum){
        this.retryIds = retryIds;
        this.attempt  = attemptNum;
    }

    /* ------------------------------------------------------------------ *
     *  State kept between execute() calls                                *
     * ------------------------------------------------------------------ */
    private DateTime     sinceDate;            // for the very first run
    private Set<Id>      retryIds;             // for retry runs
    public  Integer      attempt;              // 1 … 3
    public  Integer      uploaded = 0;
    public  Integer      skipped  = 0;
    public  Set<Id>      failedIds = new Set<Id>();

    /* ------------------------------------------------------------------ *
     *  start() – build QueryLocator                                      *
     * ------------------------------------------------------------------ */
    global Database.QueryLocator start(Database.BatchableContext bc){

        if (retryIds != null){                           // ← retry batch
            return Database.getQueryLocator(
                'SELECT ' + CV_FIELDS +
                ' FROM ContentVersion WHERE Id IN :retryIds'
            );
        }

        // normal nightly run
        String q = 'SELECT Id, ContentDocumentId, CreatedDate, ' +
           'Title, VersionNumber, FileExtension, FileType, ContentSize, ' +
           'LastModifiedDate ' +                
           'FROM ContentVersion ' +
           'WHERE IsLatest = true ' +
           'AND   LastModifiedDate >= :sinceDate';

        return Database.getQueryLocator(q);
    }

    /* ------------------------------------------------------------------ *
     *  execute() – governor-safe chunk                                   *
     * ------------------------------------------------------------------ */
    global void execute(Database.BatchableContext bc,
                        List<SObject> scope){

        /* ---- 1. Pre-fetch existing S3_File__c rows ------------------- */
        List<String> cvIds  = new List<String>();
        List<Id>     docIds = new List<Id>();
        for (ContentVersion cv : (List<ContentVersion>)scope){
            cvIds.add(cv.Id);
            docIds.add(cv.ContentDocumentId);
        }

        Map<String,S3_File__c> existing = new Map<String,S3_File__c>();
        for (S3_File__c s3 : [
            SELECT Id, Content_Version_ID__c, Content_Modified__c
            FROM   S3_File__c
            WHERE  Content_Version_ID__c IN :cvIds
        ]){
            existing.put(s3.Content_Version_ID__c, s3);
        }

        /* ---- 2. Linked-entity look-ups (Account / Case …) ------------ */
        Map<Id,Id> acc = new Map<Id,Id>(),
                   opp = new Map<Id,Id>(),
                   cas = new Map<Id,Id>(),
                   con = new Map<Id,Id>(),
                   tsk = new Map<Id,Id>();

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM   ContentDocumentLink
            WHERE  ContentDocumentId IN :docIds
        ]){
            String t = cdl.LinkedEntityId.getSObjectType()
                                         .getDescribe().getName();
            if      (t=='Account'     && !acc.containsKey(cdl.ContentDocumentId))
                acc.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            else if (t=='Opportunity' && !opp.containsKey(cdl.ContentDocumentId))
                opp.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            else if (t=='Case'        && !cas.containsKey(cdl.ContentDocumentId))
                cas.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            else if (t=='Contact'     && !con.containsKey(cdl.ContentDocumentId))
                con.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            else if (t=='Task'        && !tsk.containsKey(cdl.ContentDocumentId))
                tsk.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }

        /* ---- 3. Work each CV ----------------------------------------- */
        List<S3_File__c> toUpsert = new List<S3_File__c>();

        for (ContentVersion cv : (List<ContentVersion>)scope){
            try{
                S3_File__c rec = FileSyncWorker.sync(cv, existing);

                if (rec == null){        // nothing changed
                    skipped++;
                    continue;
                }

                /* enrich with extra metadata */
                Id docId = cv.ContentDocumentId;
                rec.Creation_Date__c = cv.CreatedDate.date();
                rec.Creation_Year__c = cv.CreatedDate.year();
                if (acc.containsKey(docId)) rec.Account_ID__c     = acc.get(docId);
                if (opp.containsKey(docId)) rec.Opportunity_ID__c = opp.get(docId);
                if (cas.containsKey(docId)) rec.Case_ID__c        = cas.get(docId);
                if (con.containsKey(docId)) rec.Contact_ID__c     = con.get(docId);
                if (tsk.containsKey(docId)) rec.Task_ID__c        = tsk.get(docId);

                toUpsert.add(rec);
                uploaded++;
            }
            catch (Exception e){
                failedIds.add(cv.Id);
                System.debug('sync FAILED for CV ' + cv.Id + ': ' + e.getMessage());
            }
        }

        if (!toUpsert.isEmpty()){
            upsert toUpsert Content_Version_ID__c;
        }
    }

    /* ------------------------------------------------------------------ *
     *  finish() – summary + optional retry                               *
     * ------------------------------------------------------------------ */
    global void finish(Database.BatchableContext bc){

        System.debug('FileSyncBatch run #' + attempt +
                     ' – uploaded=' + uploaded +
                     ', skipped='  + skipped +
                     ', failed='   + failedIds.size());

        /* -------- simple e-mail summary ------------------------------ */
        try{
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses( new String[]{ 'ops@example.com' } );   // CHANGE
            m.setSubject('File-Sync summary – attempt ' + attempt);
            m.setPlainTextBody(
                'Uploaded : ' + uploaded + '\n' +
                'Skipped  : ' + skipped  + '\n' +
                'Failed   : ' + failedIds.size() + '\n' +
                (failedIds.isEmpty() ? '' :
                 'Failed Ids : ' + String.join(
                       new List<Id>(failedIds), ',') + '\n')
            );
            Messaging.sendEmail( new Messaging.SingleEmailMessage[]{ m } );
        }catch (Exception mailEx){
            System.debug('E-mail could not be sent: ' + mailEx.getMessage());
        }

        /* -------- automatic retry (max 3 attempts) ------------------- */
        if (!failedIds.isEmpty() && attempt < 3){
            System.debug('Re-queuing retry batch – attempt ' + (attempt+1));
            Database.executeBatch(
                new FileSyncBatch(failedIds, attempt + 1),
                20                                   // smaller scope
            );
        }
    }

    /* ------------------------------------------------------------------ *
     *  Helper – field list                                               *
     * ------------------------------------------------------------------ */
    private static final String CV_FIELDS =
        'Id, ContentDocumentId, CreatedDate, Title, VersionNumber, ' +
        'FileExtension, FileType, ContentSize, LastModifiedDate, VersionData';
}