public with sharing class FileSyncWorker {

    // ---------- CONFIG -------------------------------------------------
    private static final String  NC           = 'AWS_S3';            // Named Credential
    private static final String  DIR          = 'salesforce-sync/';  // folder prefix in S3
    private static final Integer TIMEOUT_MS   = 30000;
    @TestVisible static Long MAX_DIRECT_BYTES = 6L * 1024L * 1024L;

    /**
     * PUTs to S3 and returns the S3_File__c to upsert,
     * or returns NULL when:
     *   • nothing changed, or
     *   • file is "big" → a Pending_Upload__c is inserted instead.
     */
    public static S3_File__c sync(ContentVersion cv,
                                  Map<String,S3_File__c> existingMap){

        S3_File__c existing = existingMap.get((String)cv.Id);

        // --- 1) already up-to-date? ------------------------------------
        if (existing != null &&
            existing.Content_Modified__c != null &&
            cv.LastModifiedDate <= existing.Content_Modified__c){
            return null;
        }

        // --- 2) build human-readable S3 key ----------------------------
        String ext       = (cv.FileExtension == null ? '' : cv.FileExtension.toLowerCase());
        String baseTitle = String.isBlank(cv.Title) ? 'file' : cv.Title;
        String safeTitle = baseTitle.replaceAll('[^A-Za-z0-9._-]+','_').left(120);

        String key = DIR + safeTitle + '-v' + cv.VersionNumber + (String.isBlank(ext) ? '' : '.' + ext);

        // --- 3) small vs big decision ---------------------------------
        if (cv.ContentSize != null && cv.ContentSize > MAX_DIRECT_BYTES) {
            // BIG FILE → create a Pending_Upload__c row for the LWC to process later
            RelatedRefs refs = findRelated(cv.Id);

            Pending_Upload__c pending = new Pending_Upload__c(
                Name                    = key,                  // or keep your Auto-Number
                Content_Version_ID__c   = cv.Id,
                S3_Key__c               = key,
                Mime_Type__c            = mime(ext),
                Size__c                 = cv.ContentSize,
                Status__c               = 'Pending',
                Account_ID__c           = refs.accountId,
                Opportunity_ID__c       = refs.opportunityId,
                Case_ID__c              = refs.caseId,
                Contact_ID__c           = refs.contactId,
                Task_Id__c              = refs.taskId
            );
            insert pending;

            System.debug(LoggingLevel.INFO,
                'Deferred big file to Pending_Upload__c: ' + pending.Id + ' (cv=' + cv.Id + ', size=' + cv.ContentSize + ')');

            // Signal to the caller there’s no S3_File__c upsert on this pass
            return null;
        }

        // --- 4) SMALL FILE → direct PUT via Named Credential -----------
        Blob body = [SELECT VersionData FROM ContentVersion WHERE Id = :cv.Id].VersionData;
        singlePut(key, body, ext);

        // --- 5) build S3_File__c payload for upsert --------------------
        S3_File__c up = (existing == null) ? new S3_File__c()
                                           : existing.clone(false, true, true, true);
        up.Content_Version_ID__c = cv.Id;
        up.Name                  = cv.Title;
        up.Size__c               = cv.ContentSize;
        up.Type__c               = cv.FileType;
        up.Content_Modified__c   = cv.LastModifiedDate;
        up.Last_Synched__c       = System.now();
        up.S3_Key__c             = key;

        return up;
    }

    /* ------------ helper: single PUT (≤ 6 MB) ---------------------------- */
    private static void singlePut(String key, Blob body, String ext){
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NC + '/' + EncodingUtil.urlEncode(key, 'UTF-8').replace('%2F','/'));
        req.setMethod('PUT');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', mime(ext));
        req.setBodyAsBlob(body);

        HttpResponse res = new Http().send(req);
        Integer code = res == null ? null : res.getStatusCode();
        if (code == null || code != 200){
            String status = res == null ? 'No response' : res.getStatus();
            String bodyTxt = res == null ? '' : res.getBody();
            throw new FileSyncException('S3 PUT failed – code=' + code + ', status=' + status + ', body=' + bodyTxt);
        }
    }

    /* ------------ helper: find related records via ContentDocumentLink ---- */
    private class RelatedRefs {
        Id accountId;
        Id opportunityId;
        Id caseId;
        Id contactId;
        String taskId; // text
    }

    private static RelatedRefs findRelated(Id contentVersionId){
        RelatedRefs out = new RelatedRefs();

        // Get the ContentDocumentId then any links
        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        // Pull a few links; fill first match for each type (if any)
        for (ContentDocumentLink l : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId
            LIMIT 50
        ]) {
            String t = l.LinkedEntityId.getSObjectType().getDescribe().getName();  // ← robust
            if (t == 'Account'     && out.accountId == null)     out.accountId     = l.LinkedEntityId;
            if (t == 'Opportunity' && out.opportunityId == null) out.opportunityId = l.LinkedEntityId;
            if (t == 'Case'        && out.caseId == null)        out.caseId        = l.LinkedEntityId;
            if (t == 'Contact'     && out.contactId == null)     out.contactId     = l.LinkedEntityId;
            if (t == 'Task'        && out.taskId == null)        out.taskId        = (String)l.LinkedEntityId;
        }

        return out;
    }

    /* helper – minimal MIME lookup */
    private static String mime(String ext){
        ext = (ext==null?'':ext.toLowerCase());
        if (ext=='png')  return 'image/png';
        if (ext=='jpg'||ext=='jpeg') return 'image/jpeg';
        if (ext=='pdf')  return 'application/pdf';
        if (ext=='gif')  return 'image/gif';
        if (ext=='docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (ext=='msg')  return 'application/vnd.ms-outlook';
        if (ext=='eml')  return 'message/rfc822';
        return 'application/octet-stream';
    }

    public class FileSyncException extends Exception{}
}
