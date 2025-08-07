@IsTest
private class S3DocServiceTest {

    /* ---------------- helpers ---------------- */
    private static S3_File__c makeFile(String name, Id pid) {
        System.debug('[TEST] create file ' + name);
        return new S3_File__c(
            Name = name,
            S3_Key__c = name,
            Size__c = 10,
            Type__c = 'image/png',
            Creation_Year__c = 2025,
            Record_ID__c = pid
        );
    }

    /* Mock PNG bytes */
    class PngMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('[MOCK] PngMock ' + req.getEndpoint());
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','image/png');
            // tiny 1×1 transparent pixel
            Blob png = EncodingUtil.base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA' +
                'ASsJTYQAAAAASUVORK5CYII=');
            r.setBodyAsBlob(png);
            return r;
        }
    }

    /* Mock text failure (404) */
    class FailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(404);
            r.setBody('Not Found');
            return r;
        }
    }

    /* ---------------- getDocs ---------------- */
    @IsTest
    static void testGetDocs() {
        Account a = new Account(Name='Parent'); insert a;
        insert new List<S3_File__c>{
            makeFile('img1.png', a.Id),
            makeFile('img2.png', a.Id)
        };

        Test.startTest();
        List<Map<String,Object>> rows = S3DocService.getDocs(a.Id);
        Test.stopTest();

        System.debug('[SERVICE] getDocs rows: ' + rows);
        System.assertEquals(2, rows.size());

        // verify the returned records include our inserted file names
        Set<String> names = new Set<String>();
        for (Map<String,Object> r : rows) {
            names.add((String)r.get('Name'));
        }
        System.assertEquals(new Set<String>{'img1.png','img2.png'}, names);
    }

    /* ---------------- getFile success  ---------------- */
    @IsTest
    static void testGetFileSuccess() {
        Test.setMock(HttpCalloutMock.class, new PngMock());

        Test.startTest();
        S3DocService.FilePayload fp = S3DocService.getFile('img.png');
        Test.stopTest();

        System.debug('[SERVICE] getFile contentType: ' + fp.contentType);
        System.assertEquals('image/png', fp.contentType);
        System.assert(fp.base64Data.startsWith('iVBOR'), 'Base64 should start with PNG magic');
    }

    /* ---------------- getFile failure  ---------------- */
    @IsTest
    static void testGetFileFailure() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Boolean thrown = false;
        try {
            Test.startTest();
            S3DocService.getFile('missing.txt');
            Test.stopTest();
        } catch (Exception e) {
            System.debug('[SERVICE] expected failure: ' + e.getMessage());
            thrown = true;
        }
        System.assert(thrown, 'Exception expected for 404');
    }
    
        /* ---------------- updateDescriptions ---------------- */
    @IsTest
    static void testUpdateDescriptions() {

        /* 1.  Prepare data */
        Account acc = new Account(Name = 'Parent-Update'); insert acc;

        S3_File__c file1 = new S3_File__c(
            Name = 'doc1.txt', Size__c = 100, Type__c = 'text/plain',
            Creation_Year__c = 2025, Record_ID__c = acc.Id,
            Description__c = 'old'
        );
        S3_File__c file2 = new S3_File__c(
            Name = 'doc2.txt', Size__c = 200, Type__c = 'text/plain',
            Creation_Year__c = 2025, Record_ID__c = acc.Id,
            Description__c = 'old'
        );
        insert new List<S3_File__c>{ file1, file2 };

        /* 2.  Call service */
        List<S3_File__c> drafts = new List<S3_File__c>{
            new S3_File__c(Id = file1.Id, Description__c = 'new-1'),
            new S3_File__c(Id = file2.Id, Description__c = 'new-2')
        };

        Test.startTest();
        S3DocService.updateDescriptions(drafts);
        Test.stopTest();

        /* 3.  Verify */
        Map<Id,S3_File__c> after =
            new Map<Id,S3_File__c>([SELECT Description__c FROM S3_File__c
                                    WHERE Id IN :drafts]);

        System.debug('[TEST] after update: ' + after);
        System.assertEquals('new-1', after.get(file1.Id).Description__c);
        System.assertEquals('new-2', after.get(file2.Id).Description__c);
    }
    @IsTest
    static void testGetOpportunities() {
        Opportunity o = new Opportunity(Name='Test Opp', StageName='Prospecting', CloseDate=Date.today());
        insert o;
        Test.startTest();
        List<Opportunity> opps = S3DocService.getOpportunities();
        Test.stopTest();
        System.assert(!opps.isEmpty(), 'Should return at least one Opportunity');
        System.assert(opps[0].Id != null, 'Returned Opportunity should have Id');
    }
    
    @IsTest
    static void testGetCases() {
        Case c = new Case(Status='New', Origin='Web', Subject='Test');
        insert c;
        Test.startTest();
        List<Case> cases = S3DocService.getCases();
        Test.stopTest();
        System.assert(!cases.isEmpty(), 'Should return at least one Case');
        System.assert(cases[0].Id != null, 'Returned Case should have Id');
    }
    
    @IsTest
    static void testGetContacts() {
        Account a = new Account(Name='Test Account');
        insert a;
        Contact ct = new Contact(LastName='Test Contact', AccountId=a.Id);
        insert ct;
        Test.startTest();
        List<Contact> contacts = S3DocService.getContacts();
        Test.stopTest();
        System.assert(!contacts.isEmpty(), 'Should return at least one Contact');
        System.assert(contacts[0].Id != null, 'Returned Contact should have Id');
    }
}