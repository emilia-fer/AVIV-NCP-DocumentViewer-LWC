@IsTest
private class FileUploadJobTest {

    /* ========================= helpers ========================= */

    private static Blob smallBlob() {
        String ten = '0123456789'; // 10 bytes
        String chunk = '';
        for (Integer i = 0; i < 10000; i++) chunk += ten;  // ~100 KB
        return Blob.valueOf(chunk);
    }

    private static Blob exact6MBBlob() {
        Integer target = 6 * 1024 * 1024; // 6,291,456 bytes
        String ten = '0123456789'; // 10 bytes
        String oneHundredKb = '';
        for (Integer i = 0; i < 10000; i++) oneHundredKb += ten; // ~100 KB

        List<String> parts = new List<String>();
        Integer full = target / oneHundredKb.length();
        for (Integer i = 0; i < full; i++) parts.add(oneHundredKb);

        Integer rem = target - full * oneHundredKb.length();
        if (rem > 0) parts.add(oneHundredKb.substring(0, rem));

        Blob b = Blob.valueOf(String.join(parts,''));
        System.assertEquals(target, b.size(), 'sanity check exact 6MB');
        return b;
    }

    private static Blob bigBlob() {
        Integer target = 6 * 1024 * 1024 + 16 * 1024; // 6 MB + 16 KB
        String ten = '0123456789';
        String oneHundredKb = '';
        for (Integer i = 0; i < 10000; i++) oneHundredKb += ten; // ~100 KB
        List<String> parts = new List<String>();
        Integer full = target / oneHundredKb.length();
        for (Integer i = 0; i < full; i++) parts.add(oneHundredKb);
        Integer rem = target - full * oneHundredKb.length();
        if (rem > 0) parts.add(oneHundredKb.substring(0, rem));
        return Blob.valueOf(String.join(parts,''));
    }

    private static ContentVersion insertCV(String title, Blob data) {
        insert new ContentVersion(
            Title          = title,
            PathOnClient   = title,
            VersionData    = data,
            IsMajorVersion = true
        );
        ContentVersion cv = [
            SELECT Id, VersionNumber, ContentSize
            FROM   ContentVersion
            WHERE  Title = :title
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.debug('Test: Inserted CV ' + cv.Id + ' size=' + cv.ContentSize);
        return cv;
    }

    private static Map<String, Id> seedRelated() {
        Account a = new Account(Name = 'Acme Inc.');
        insert a;
        Opportunity o = new Opportunity(
            Name='Test Opp', StageName='Prospecting',
            CloseDate=Date.today().addDays(30), AccountId=a.Id
        );
        insert o;
        Contact c = new Contact(LastName='Smith', AccountId=a.Id);
        insert c;
        Case cs = new Case(Subject='Unit case', AccountId=a.Id);
        insert cs;
        System.debug('Test: Seeded refs A=' + a.Id + ' O=' + o.Id + ' C=' + c.Id + ' Case=' + cs.Id);
        return new Map<String, Id>{
            'AccountId'     => a.Id,
            'OpportunityId' => o.Id,
            'ContactId'     => c.Id,
            'CaseId'        => cs.Id
        };
    }

    /* ======================= HTTP mocks ======================== */

    private class MockPutOK implements HttpCalloutMock {
        public Integer putCount = 0;
        public String  lastEndpoint;
        public String  lastContentType;

        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockPutOK: ' + req.getMethod() + ' ' + req.getEndpoint());
            lastEndpoint   = req.getEndpoint();
            lastContentType= req.getHeader('Content-Type');

            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'PUT') {
                putCount++;
                res.setStatusCode(200);
                res.setStatus('OK');
                res.setBody('OK');
                return res;
            }
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('OK');
            return res;
        }
    }

    private class MockPutFail implements HttpCalloutMock {
        public Integer putCount = 0;

        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockPutFail: ' + req.getMethod() + ' ' + req.getEndpoint());
            HttpResponse res = new HttpResponse();
            if (req.getMethod() == 'PUT') {
                putCount++;
                res.setStatusCode(500);
                res.setStatus('Internal Server Error');
                res.setBody('Boom from mock');
                return res;
            }
            res.setStatusCode(200);
            res.setStatus('OK');
            res.setBody('OK');
            return res;
        }
    }

    private class MockThrows implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockThrows: ' + req.getMethod() + ' ' + req.getEndpoint());
            // Simulate a network/auth failure
            throw new System.CalloutException('Simulated network failure');
        }
    }

    /* =========================== TESTS ========================= */

    @IsTest
    static void smallFile_directPut_success() {
        ContentVersion cv = insertCV('small.txt', smallBlob());
        System.assert(cv.ContentSize < 6 * 1024 * 1024);
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        MockPutOK mock = new MockPutOK();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'text/plain', null, null, null, null, null
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.debug('Test result small success: status=' + j.Status + ' errors=' + j.NumberOfErrors + ' PUTs=' + mock.putCount);
        System.assertEquals('Completed', j.Status);
        System.assertEquals(0, j.NumberOfErrors);
        System.assertEquals(1, mock.putCount);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Upload__c]);
    }

    @IsTest
    static void smallFile_directPut_failure_marksJobFailed() {
        ContentVersion cv = insertCV('small-fail.txt', smallBlob());
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        MockPutFail mock = new MockPutFail();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'text/plain', null, null, null, null, null
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.debug('Test result small fail: status=' + j.Status + ' errors=' + j.NumberOfErrors + ' PUTs=' + mock.putCount);
        System.assertEquals('Failed', j.Status);
        System.assert(j.NumberOfErrors > 0);
        System.assertEquals(1, mock.putCount);
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Upload__c]);
    }

    @IsTest
    static void bigFile_createsPendingUpload_withLinks() {
        Map<String, Id> refs = seedRelated();
        ContentVersion cv = insertCV('big.txt', bigBlob());
        System.assert(cv.ContentSize > 6 * 1024 * 1024);
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        Test.setMock(HttpCalloutMock.class, new MockPutOK());

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'text/plain',
            refs.get('AccountId'), refs.get('OpportunityId'),
            refs.get('CaseId'), refs.get('ContactId'), '00TXXXXXXXXXXXX'
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.debug('Test result big/pending: status=' + j.Status + ' errors=' + j.NumberOfErrors);
        System.assertEquals('Completed', j.Status);
        System.assertEquals(0, j.NumberOfErrors);

        Pending_Upload__c p = [
            SELECT Id, S3_Key__c, Mime_Type__c, Size__c, Status__c,
                   Account_ID__c, Opportunity_ID__c, Case_ID__c, Contact_ID__c, Task_Id__c
            FROM   Pending_Upload__c
            WHERE  Content_Version_ID__c = :cv.Id
            LIMIT 1
        ];
        System.debug('Pending row: ' + p);

        System.assertEquals(key,            p.S3_Key__c);
        System.assertEquals('text/plain',   p.Mime_Type__c);
        System.assertEquals(cv.ContentSize, p.Size__c);
        System.assertEquals('Pending',      p.Status__c);
        System.assertEquals(refs.get('AccountId'),     p.Account_ID__c);
        System.assertEquals(refs.get('OpportunityId'), p.Opportunity_ID__c);
        System.assertEquals(refs.get('CaseId'),        p.Case_ID__c);
        System.assertEquals(refs.get('ContactId'),     p.Contact_ID__c);
        System.assertEquals('00TXXXXXXXXXXXX',         p.Task_Id__c);
    }

    @IsTest
    static void smallFile_endpointEncoding_preservesSlashes_encodesSpaces() {
        ContentVersion cv = insertCV('name with spaces.txt', smallBlob());
        String key = 'salesforce-sync/folder 1/sub folder 2/file name.txt';

        MockPutOK mock = new MockPutOK();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'text/plain', null, null, null, null, null
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', j.Status);
        System.assertNotEquals(null, mock.lastEndpoint, 'mock should capture endpoint');

        System.assert(
            mock.lastEndpoint.contains('folder%201/sub%20folder%202/file%20name.txt'),
            'Endpoint should encode spaces but keep slashes: ' + mock.lastEndpoint
        );
        System.assertEquals(-1, mock.lastEndpoint.indexOf('%2F'),
            'Endpoint must not contain %2F (slashes must be preserved)');
    }

    @IsTest
    static void smallFile_calloutThrows_marksJobFailed() {
        ContentVersion cv = insertCV('small-throws.txt', smallBlob());
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        Test.setMock(HttpCalloutMock.class, new MockThrows());

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'text/plain', null, null, null, null, null
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Failed', j.Status);
        System.assert(j.NumberOfErrors > 0);
    }

    @IsTest
    static void exactThreshold_6MB_isStillDirectPut() {
        ContentVersion cv = insertCV('exact6MB.bin', exact6MBBlob());
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.bin';

        MockPutOK mock = new MockPutOK();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Id jobId = System.enqueueJob(new FileUploadJob(
            cv.Id, key, 'application/octet-stream', null, null, null, null, null
        ));
        Test.stopTest();

        AsyncApexJob j = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', j.Status);
        System.assertEquals(1, mock.putCount, 'Exact threshold should still direct PUT');
        System.assertEquals(0, [SELECT COUNT() FROM Pending_Upload__c]);
    }
}