@IsTest
private class S3DocServiceTest {

    /* ---------------- helpers ---------------- */
    private static S3_File__c makeFileForAccount(String name, Id accountId) {
        return new S3_File__c(
            Name               = name,
            S3_Key__c          = 'folder 1/' + name, // include a space to test encoding later
            Size__c            = 10,
            Type__c            = 'image/png',
            Creation_Year__c   = 2025,
            Account_ID__c      = accountId
        );
    }
    private static S3_File__c makeFileForAllParents(String name, Id acct, Id opp, Id cs, Id ct, Id taskId) {
        return new S3_File__c(
            Name               = name,
            S3_Key__c          = 'parent/sub/' + name,
            Size__c            = 11,
            Type__c            = 'application/pdf',
            Creation_Year__c   = 2025,
            Account_ID__c      = acct,
            Opportunity_ID__c  = opp,
            Case_ID__c         = cs,
            Contact_ID__c      = ct,
            Task_ID__c         = (String)taskId
        );
    }

    /* ---------- HTTP mocks ---------- */

    // 200 OK with PNG body, and records the last endpoint we were called with
    private class RecordingOkMock implements HttpCalloutMock {
        public String lastEndpoint;
        public HTTPResponse respond(HTTPRequest req) {
            lastEndpoint = req.getEndpoint();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type','image/png');
            Blob png = EncodingUtil.base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMA' +
                'ASsJTYQAAAAASUVORK5CYII=');
            r.setBodyAsBlob(png);
            return r;
        }
    }

    // 200 OK with no Content-Type to exercise the default MIME branch
    private class NoMimeOkMock implements HttpCalloutMock {
        public String lastEndpoint;
        public HTTPResponse respond(HTTPRequest req) {
            lastEndpoint = req.getEndpoint();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setBody('hello'); // text → bodyAsBlob still fine
            return r;
        }
    }

    // Non-200
    private class FailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(404);
            r.setStatus('Not Found');
            r.setBody('Nope');
            return r;
        }
    }

    /* ---------------- getDocs ---------------- */
    @IsTest
    static void getDocs_includesTaskUrlAndSubject_andFiltersByAnyParent() {
        Account a = new Account(Name='Parent'); insert a;
        Opportunity o = new Opportunity(Name='Opp', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id); insert o;
        Contact ct = new Contact(LastName='C', AccountId=a.Id); insert ct;
        Case cs = new Case(Status='New', Origin='Web', Subject='S', AccountId=a.Id); insert cs;
        Task t = new Task(Subject='Follow up', Status='Completed'); insert t;

        insert new List<S3_File__c>{
            makeFileForAccount('img1.png', a.Id),
            makeFileForAllParents('bundle.pdf', a.Id, o.Id, cs.Id, ct.Id, t.Id)
        };

        Test.startTest();
        List<Map<String,Object>> rows = S3DocService.getDocs(a.Id);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'should return both rows tied to this Account (direct and via other parents)');

        // Find the one with the Task and verify enrichment
        Boolean sawTask = false;
        for (Map<String,Object> r : rows) {
            if ((String)r.get('Name') == 'bundle.pdf') {
                sawTask = true;
                System.assertEquals('/' + String.valueOf(t.Id), (String)r.get('TaskUrl'));
                System.assertEquals('Follow up', (String)r.get('TaskName'));
            }
        }
        System.assert(sawTask, 'Expected to see the row with Task enrichment');
    }

    /* ---------------- getFile ---------------- */

    @IsTest
    static void getFile_success_recordsEncodedEndpoint_andMimeFromHeader() {
        RecordingOkMock mock = new RecordingOkMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        // include spaces and slashes to verify segment encoding (spaces -> %20; slashes preserved)
        S3DocService.FilePayload fp = S3DocService.getFile('a folder/child file.png');
        Test.stopTest();

        System.assertEquals('image/png', fp.contentType, 'should use header MIME when provided');
        System.assert(fp.base64Data.startsWith('iVBOR'), 'PNG signature expected');

        System.assertNotEquals(null, mock.lastEndpoint);
        // Must be callout:AWS_S3/<segments URL-encoded with spaces as %20, slashes intact>
        System.assert(mock.lastEndpoint.startsWith('callout:AWS_S3/'));
        System.assert(mock.lastEndpoint.contains('a%20folder/child%20file.png'),
            'Expected spaces encoded and slashes preserved, got: ' + mock.lastEndpoint);
        System.assertEquals(-1, mock.lastEndpoint.indexOf('%2F'), 'No %2F allowed (slashes must be preserved)');
    }

    @IsTest
    static void getFile_success_defaultMimeWhenMissing() {
        NoMimeOkMock mock = new NoMimeOkMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3DocService.FilePayload fp = S3DocService.getFile('no-mime/hello.bin');
        Test.stopTest();

        System.assertEquals('application/octet-stream', fp.contentType, 'missing header should default MIME');
    }

    @IsTest
    static void getFile_blankKey_throws() {
        Boolean thrown = false;
        try {
            Test.startTest();
            S3DocService.getFile('');
            Test.stopTest();
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'blank key must throw AuraHandledException');
    }

    @IsTest
    static void getFile_non200_throws() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Boolean thrown = false;
        try {
            Test.startTest();
            S3DocService.getFile('missing.txt');
            Test.stopTest();
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'non-200 must throw AuraHandledException');
    }

    /* ---------------- updateDescriptions ---------------- */
    @IsTest
    static void updateDescriptions_onlyDescriptionIsUpdated() {
        Account acc = new Account(Name = 'A'); insert acc;

        S3_File__c f1 = new S3_File__c(
            Name='doc1.txt', Size__c=1, Type__c='text/plain', Creation_Year__c=2025, Account_ID__c=acc.Id, Description__c='old1'
        );
        S3_File__c f2 = new S3_File__c(
            Name='doc2.txt', Size__c=2, Type__c='text/plain', Creation_Year__c=2025, Account_ID__c=acc.Id, Description__c='old2'
        );
        insert new List<S3_File__c>{ f1, f2 };

        List<S3_File__c> drafts = new List<S3_File__c>{
            new S3_File__c(Id=f1.Id, Description__c='new-1'),
            new S3_File__c(Id=f2.Id, Description__c='new-2')
        };

        Test.startTest();
        S3DocService.updateDescriptions(drafts);
        Test.stopTest();

        Map<Id,S3_File__c> after = new Map<Id,S3_File__c>([
            SELECT Description__c, Name, Size__c FROM S3_File__c WHERE Id IN :new List<Id>{ f1.Id, f2.Id }
        ]);

        System.assertEquals('new-1', after.get(f1.Id).Description__c);
        System.assertEquals('new-2', after.get(f2.Id).Description__c);
        // sanity: other fields unchanged
        System.assertEquals('doc1.txt', after.get(f1.Id).Name);
        System.assertEquals(1, after.get(f1.Id).Size__c);
    }

    /* ---------------- related* helpers ---------------- */

    @IsTest
    static void relatedOpportunities_forAccount() {
        Account a = new Account(Name='A'); insert a;
        Opportunity o1 = new Opportunity(Name='O1', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id);
        Opportunity o2 = new Opportunity(Name='O2', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id);
        insert new List<Opportunity>{ o1, o2 };

        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(a.Id);
        Test.stopTest();

        System.assertEquals(2, got.size(), 'Account → all opps');
    }

    @IsTest
    static void relatedOpportunities_forCase_usesCaseAccount() {
        Account a = new Account(Name='A2'); insert a;
        Opportunity o = new Opportunity(Name='O', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id); insert o;
        Case c = new Case(Status='New', Origin='Web', Subject='S', AccountId=a.Id); insert c;

        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(c.Id);
        Test.stopTest();

        System.assertEquals(1, got.size(), 'Case → opps of its account');
        System.assertEquals(o.Id, got[0].Id);
    }

    @IsTest
    static void relatedOpportunities_otherPrefixes_empty() {
        Contact ct = new Contact(LastName='C'); insert ct; // 003, but method returns empty for non-account/case
        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(ct.Id);
        Test.stopTest();
        System.assertEquals(0, got.size());
    }

    @IsTest
    static void relatedCases_forAccount_and_forContact() {
        Account a = new Account(Name='A'); insert a;
        Contact ct = new Contact(LastName='C', AccountId=a.Id); insert ct;

        Case c1 = new Case(Status='New', Origin='Web', Subject='S1', AccountId=a.Id);
        Case c2 = new Case(Status='New', Origin='Web', Subject='S2', ContactId=ct.Id);
        insert new List<Case>{ c1, c2 };

        // Account branch
        Test.startTest();
        List<Case> acctCases = S3DocService.relatedCases(a.Id);
        Test.stopTest();
        System.assert(acctCases.size() >= 1, 'Account → cases');

        // Contact branch
        Test.startTest();
        List<Case> contactCases = S3DocService.relatedCases(ct.Id);
        Test.stopTest();
        System.assertEquals(1, contactCases.size(), 'Contact → its cases');
        System.assertEquals(c2.Id, contactCases[0].Id);
    }

    @IsTest
    static void relatedCases_otherPrefixes_empty() {
        Opportunity o = new Opportunity(Name='O', StageName='Prospecting', CloseDate=Date.today()); insert o; // 006
        Test.startTest();
        List<Case> got = S3DocService.relatedCases(o.Id);
        Test.stopTest();
        System.assertEquals(0, got.size());
    }

    @IsTest
    static void relatedContacts_forAccount_andOthersEmpty() {
        Account a = new Account(Name='A'); insert a;
        Contact c1 = new Contact(LastName='C1', AccountId=a.Id);
        Contact c2 = new Contact(LastName='C2', AccountId=a.Id);
        insert new List<Contact>{ c1, c2 };

        // Account branch
        Test.startTest();
        List<Contact> contacts = S3DocService.relatedContacts(a.Id);
        Test.stopTest();
        System.assertEquals(2, contacts.size());

        // Non-account branch → empty
        Opportunity o = new Opportunity(Name='O', StageName='Prospecting', CloseDate=Date.today()); insert o;
        Test.startTest();
        List<Contact> empty = S3DocService.relatedContacts(o.Id);
        Test.stopTest();
        System.assertEquals(0, empty.size());
    }
}
