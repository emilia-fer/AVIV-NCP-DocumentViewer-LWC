/* =======================================================================
 * FileSyncBatchTest.cls          ⌁ >90 % coverage, single start/stop
 * -----------------------------------------------------------------------
 * ▸ Creates one tiny file + one 1.2 MB file
 * ▸ Executes the batch twice (upload → skip)
 * ▸ Fires the nightly scheduler
 * ▸ Uses a universal HttpCalloutMock that returns 200 for every PUT
 * ==================================================================== */
@IsTest
private class FileSyncBatchTest {

    /* ---------- Call-out mock: always 200 OK ------------------------ */
    private class S3Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req){
            HttpResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('OK');
            return res;
        }
    }

    /* ---------- helper: create a ContentVersion --------------------- */
    private static ContentVersion makeCV(String name, Blob body){
        insert new ContentVersion(
            Title          = name,
            PathOnClient   = name,
            VersionData    = body,
            IsMajorVersion = true
        );
        return [SELECT  Id, ContentDocumentId, CreatedDate,
                       Title, VersionNumber, FileExtension, FileType,
                       ContentSize, LastModifiedDate, VersionData
                FROM    ContentVersion
                WHERE   Title = :name LIMIT 1];
    }

    /* ---------- 1.2 MB blob (well below 6 MB heap) ------------------ */
    private static Blob makeLargeBlob(){
        String chunk   = '0123456789';
        Integer reps   = (1200 * 1024) / chunk.length();     // ≈1.2 MB
        String bigText = chunk.repeat(reps);
        System.debug('Large blob size (chars) = ' + bigText.length());
        return Blob.valueOf(bigText);
    }

    /* ===================================================================
     *  MASTER TEST – single start/stop block
     * ================================================================= */
    @IsTest
    static void fullFlow(){

        /* Arrange ----------------------------------------------------- */
        Test.setMock(HttpCalloutMock.class, new S3Mock());

        ContentVersion tiny  = makeCV('tiny.txt',  Blob.valueOf('abc'));
        ContentVersion large = makeCV('large.pdf', makeLargeBlob());

        DateTime sinceYesterday = System.now().addDays(-1);

        /* ---------- ONE start/stop ---------------------------------- */
        Test.startTest();

            /* 1st run – uploads both                                    */
            Database.executeBatch(new FileSyncBatch(sinceYesterday), 2);

            /* 2nd run – should skip both                                */
            Database.executeBatch(new FileSyncBatch(sinceYesterday), 2);

            /* Scheduler – queued, executes before stopTest flush        */
            System.schedule('UT-FileSync-Nightly',
                            '0 15 2 * * ?',
                            new Sched_FileSync_Nightly());

        Test.stopTest();

        /* ---------- Assertions -------------------------------------- */
        Integer rows = [SELECT COUNT() FROM S3_File__c];
        System.debug('Total S3_File__c rows after test run = ' + rows);
        System.assertEquals(2, rows,
            'Exactly two unique S3_File__c rows should exist');

        /* ensure Last_Synched__c != null (upload happened)             */
        for (S3_File__c rec :
             [SELECT Last_Synched__c FROM S3_File__c WHERE Last_Synched__c = NULL]){
            System.assert(false,
                'All records must have Last_Synched__c populated – upload happened');
        }
    }
    
    /* ──────────────────────────────────────────────────────────
     * ✓ covers the SKIP branch in FileSyncWorker
     *   (existing record newer than ContentVersion   →  null)
     * ───────────────────────────────────────────────────────── */
    @IsTest static void skipBranch(){
    
        Test.setMock(HttpCalloutMock.class, new S3Mock());
    
        /* 1. arrange – create CV + matching S3_File__c that is NEWER */
        ContentVersion cv = makeCV('skip.txt', Blob.valueOf('x'));
    
        S3_File__c existing = new S3_File__c(
            Content_Version_ID__c = cv.Id,
            Content_Modified__c   = cv.LastModifiedDate.addSeconds( 60 ), // newer
            Last_Synched__c       = System.now(),
            Name                  = cv.Title,
            Size__c               = cv.ContentSize,
            Type__c               = cv.FileType,
            S3_Key__c             = 'dummy'
        );
        insert existing;
    
        DateTime since = System.now().addDays(-1);
    
        /* 2. act */
        Test.startTest();
            Database.executeBatch(new FileSyncBatch(since), 1);
        Test.stopTest();
    
        /* 3. assert – still exactly ONE record, no duplicate */
        Integer rows = [ SELECT COUNT() FROM S3_File__c
                         WHERE Content_Version_ID__c = :cv.Id ];
        System.assertEquals(1, rows, 'skip path must not create extra rows');
    }
    
    /* ──────────────────────────────────────────────────────────
     * ✓ covers the ERROR branch in FileSyncWorker / FileSyncBatch
     *   (PUT returns 500 → FileSyncException handled in batch)
     * ───────────────────────────────────────────────────────── */
    private class S3FailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req){
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);                // simulate failure
            res.setBody('Boom.');
            return res;
        }
    }
    
    @IsTest static void putFailure(){
    
        /* arrange */
        Test.setMock(HttpCalloutMock.class, new S3FailMock());
        ContentVersion cv = makeCV('willFail.txt', Blob.valueOf('y'));
        DateTime since    = System.now().addDays(-1);
    
        /* act */
        Test.startTest();
            // We expect NO un-handled exception here – the batch
            // catches FileSyncWorker.FileSyncException internally
            Database.executeBatch(new FileSyncBatch(since), 1);
        Test.stopTest();
    
        /* assert – the failed upload did NOT create a row */
        Integer rows = [ SELECT COUNT() FROM S3_File__c
                         WHERE Content_Version_ID__c = :cv.Id ];
        System.assertEquals(0, rows,
            'failed PUT must not leave half-baked S3_File__c rows');
    }
}