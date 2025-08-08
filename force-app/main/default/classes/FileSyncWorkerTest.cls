@IsTest
private class FileSyncWorkerTest {

    /* simple mock that records call count and returns given status */
    private class CountingMock implements HttpCalloutMock {
        Integer status;
        Integer callCount = 0;
        CountingMock(Integer code){ this.status = code; }
        public HTTPResponse respond(HTTPRequest req){
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody('test');
            return res;
        }
    }

    /* helper to create and query a ContentVersion */
    private static ContentVersion makeCV(String name, Blob body){
        insert new ContentVersion(
            Title          = name,
            PathOnClient   = name,
            VersionData    = body,
            IsMajorVersion = true
        );
        return [SELECT Id, Title, VersionNumber, FileExtension, FileType,
                       ContentSize, LastModifiedDate
                FROM   ContentVersion
                WHERE  Title = :name LIMIT 1];
    }

    @IsTest static void uploadAndSkip(){

        /* -------- upload branch (200 OK) ----------------------- */
        CountingMock mock = new CountingMock(200);
        Test.setMock(HttpCalloutMock.class, mock);

        ContentVersion cv = makeCV('upload.txt', Blob.valueOf('abc'));

        Map<String,S3_File__c> emptyMap = new Map<String,S3_File__c>();
        Test.startTest();
        S3_File__c result = FileSyncWorker.sync(cv, emptyMap);  
        Test.stopTest();        

        System.assertNotEquals(null, result, 'upload should return S3_File__c');
        System.assertEquals(1, mock.callCount, 'upload should call out once');

        /* -------- skip branch (existing up-to-date) ------------ */
        mock = new CountingMock(200);
        Test.setMock(HttpCalloutMock.class, mock);
        S3_File__c existing = new S3_File__c(
            Content_Version_ID__c = cv.Id,
            Content_Modified__c   = cv.LastModifiedDate,
            Last_Synched__c       = System.now(),
            Name                  = cv.Title,
            S3_Key__c             = 'dummy'
        );
        Map<String,S3_File__c> existingMap = new Map<String,S3_File__c>{
            (String)cv.Id => existing
        };
        S3_File__c skipped = FileSyncWorker.sync(cv, existingMap);
        System.assertEquals(null, skipped, 'skip should return null');
        System.assertEquals(0, mock.callCount, 'skip should not call out');
    }

    @IsTest static void uploadError(){
        CountingMock mock = new CountingMock(500);
        Test.setMock(HttpCalloutMock.class, mock);

        ContentVersion cv = makeCV('error.txt', Blob.valueOf('xyz'));

        try{
            Test.startTest();
            FileSyncWorker.sync(cv, new Map<String,S3_File__c>());
            Test.stopTest();
            System.assert(false, 'Expected FileSyncException');
        }catch (FileSyncWorker.FileSyncException e){
            System.assert(e.getMessage().contains('S3 PUT failed'),
                          'error path must throw FileSyncException');
        }
        System.assertEquals(1, mock.callCount, 'error path should attempt callout');
    }
}
