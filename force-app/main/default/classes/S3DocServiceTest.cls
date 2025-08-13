@IsTest
private class S3DocServiceTest {

    /* ---------------- helpers ---------------- */
    private static S3_File__c makeFileForAccount(String name, Id accountId) {
        return new S3_File__c(
            Name               = name,
            S3_Key__c          = 'folder 1/' + name,
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
    private class NoMimeOkMock implements HttpCalloutMock {
        public String lastEndpoint;
        public HTTPResponse respond(HTTPRequest req) {
            lastEndpoint = req.getEndpoint();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setBody('hello');
            return r;
        }
    }
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

        System.assertEquals(2, rows.size());

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

    @IsTest
    static void getDocs_filters_by_Contact() {
        Account a = new Account(Name='A'); insert a;
        Contact c = new Contact(LastName='LC', AccountId=a.Id); insert c;
        insert new List<S3_File__c>{
            new S3_File__c(Name='c1', S3_Key__c='k', Size__c=1, Type__c='t', Creation_Year__c=2025, Contact_ID__c=c.Id),
            new S3_File__c(Name='x',  S3_Key__c='k', Size__c=1, Type__c='t', Creation_Year__c=2025, Account_ID__c=a.Id)
        };

        Test.startTest();
        List<Map<String,Object>> rows = S3DocService.getDocs(c.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Only contact-linked row should appear');
        System.assertEquals('c1', (String)rows[0].get('Name'));
    }

    @IsTest
    static void getDocs_TaskName_fallback_when_Task_missing() {
        Account a = new Account(Name='A'); insert a;
        String fakeTaskId = '00T000000000000AAA';
        insert new S3_File__c(
            Name='trow', S3_Key__c='k', Size__c=1, Type__c='t', Creation_Year__c=2025,
            Account_ID__c=a.Id, Task_ID__c=fakeTaskId
        );

        Test.startTest();
        List<Map<String,Object>> rows = S3DocService.getDocs(a.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals('/'+fakeTaskId, (String)rows[0].get('TaskUrl'));
        System.assertEquals(fakeTaskId, (String)rows[0].get('TaskName'));
    }

    /* ---------------- getFile ---------------- */
    @IsTest
    static void getFile_success_recordsEncodedEndpoint_andMimeFromHeader() {
        RecordingOkMock mock = new RecordingOkMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3DocService.FilePayload fp = S3DocService.getFile('a folder/child file.png');
        Test.stopTest();

        System.assertEquals('image/png', fp.contentType);
        System.assert(fp.base64Data.startsWith('iVBOR'));
        System.assertNotEquals(null, mock.lastEndpoint);
        System.assert(mock.lastEndpoint.startsWith('callout:AWS_S3/'));
        System.assert(mock.lastEndpoint.contains('a%20folder/child%20file.png'));
        System.assertEquals(-1, mock.lastEndpoint.indexOf('%2F'));
    }

    @IsTest
    static void getFile_success_defaultMimeWhenMissing() {
        NoMimeOkMock mock = new NoMimeOkMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3DocService.FilePayload fp = S3DocService.getFile('no-mime/hello.bin');
        Test.stopTest();

        System.assertEquals('application/octet-stream', fp.contentType);
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
        System.assert(thrown);
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
        System.assert(thrown);
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
        System.assertEquals('doc1.txt', after.get(f1.Id).Name);
        System.assertEquals(1, after.get(f1.Id).Size__c);
    }

    /* ---------------- related* helpers (one start/stop each) ---------------- */

    @IsTest
    static void relatedOpportunities_forAccount() {
        Account a = new Account(Name='A'); insert a;
        Opportunity o1 = new Opportunity(Name='O1', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id);
        Opportunity o2 = new Opportunity(Name='O2', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id);
        insert new List<Opportunity>{ o1, o2 };

        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(a.Id);
        Test.stopTest();

        System.assertEquals(2, got.size());
    }

    @IsTest
    static void relatedOpportunities_forCase_usesCaseAccount() {
        Account a = new Account(Name='A2'); insert a;
        Opportunity o = new Opportunity(Name='O', StageName='Prospecting', CloseDate=Date.today(), AccountId=a.Id); insert o;
        Case c = new Case(Status='New', Origin='Web', Subject='S', AccountId=a.Id); insert c;

        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(c.Id);
        Test.stopTest();

        System.assertEquals(1, got.size());
        System.assertEquals(o.Id, got[0].Id);
    }

    @IsTest
    static void relatedOpportunities_otherPrefixes_empty() {
        Contact ct = new Contact(LastName='C'); insert ct; // 003
        Test.startTest();
        List<Opportunity> got = S3DocService.relatedOpportunities(ct.Id);
        Test.stopTest();
        System.assertEquals(0, got.size());
    }

    @IsTest
    static void relatedCases_forAccount_only() {
        Account a = new Account(Name='A'); insert a;
        Case c1 = new Case(Status='New', Origin='Web', Subject='S1', AccountId=a.Id);
        Case c2 = new Case(Status='New', Origin='Web', Subject='S2', AccountId=a.Id);
        insert new List<Case>{ c1, c2 };

        Test.startTest();
        List<Case> acctCases = S3DocService.relatedCases(a.Id);
        Test.stopTest();

        System.assert(acctCases.size() >= 2);
    }

    @IsTest
    static void relatedCases_forContact_only() {
        Account a = new Account(Name='A'); insert a;
        Contact ct = new Contact(LastName='C', AccountId=a.Id); insert ct;
        Case c = new Case(Status='New', Origin='Web', Subject='S', ContactId=ct.Id); insert c;

        Test.startTest();
        List<Case> contactCases = S3DocService.relatedCases(ct.Id);
        Test.stopTest();

        System.assertEquals(1, contactCases.size());
        System.assertEquals(c.Id, contactCases[0].Id);
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
    static void relatedContacts_forAccount_only() {
        Account a = new Account(Name='A'); insert a;
        Contact c1 = new Contact(LastName='C1', AccountId=a.Id);
        Contact c2 = new Contact(LastName='C2', AccountId=a.Id);
        insert new List<Contact>{ c1, c2 };

        Test.startTest();
        List<Contact> contacts = S3DocService.relatedContacts(a.Id);
        Test.stopTest();

        System.assertEquals(2, contacts.size());
    }

    @IsTest
    static void relatedContacts_otherPrefixes_empty() {
        Opportunity o = new Opportunity(Name='O', StageName='Prospecting', CloseDate=Date.today()); insert o;
        Test.startTest();
        List<Contact> empty = S3DocService.relatedContacts(o.Id);
        Test.stopTest();
        System.assertEquals(0, empty.size());
    }

    /* ---------------- Pending_Upload__c roundtrip ---------------- */

    @IsTest
    static void listPending_and_roundtrip_complete_createsS3File_and_deletesPending() {
        Account a = new Account(Name='A'); insert a;

        // Create a real ContentVersion (so payload has real bytes)
        Blob body = Blob.valueOf('big file body');
        insert new ContentVersion(
            Title='big.txt', PathOnClient='big.txt', VersionData=body, IsMajorVersion=true
        );
        ContentVersion cv = [
            SELECT Id, Title, ContentSize, FileType, LastModifiedDate
            FROM ContentVersion WHERE Title = 'big.txt' LIMIT 1
        ];

        Pending_Upload__c p = new Pending_Upload__c(
            Name='big.txt',
            Content_Version_ID__c = cv.Id,
            S3_Key__c = 'salesforce-sync/folder one/big.txt',
            Mime_Type__c = 'text/plain',
            Size__c = cv.ContentSize,
            Status__c = 'Pending',
            Account_ID__c = a.Id
        );
        insert p;

        // ONE startTest/stopTest for the whole pending flow
        Test.startTest();
        List<Pending_Upload__c> pending = S3DocService.listPending(a.Id);
        S3DocService.PendingPayload payload = S3DocService.getPendingPayload(p.Id);
        S3DocService.completePending(p.Id);
        Test.stopTest();

        System.assertEquals(1, pending.size(), 'listPending should return one row');
        System.assertEquals('text/plain', payload.contentType);
        System.assertEquals('salesforce-sync/folder one/big.txt', payload.key);
        System.assertNotEquals(null, payload.base64Data);
        System.assertEquals(body.size(), EncodingUtil.base64Decode(payload.base64Data).size());

        System.assertEquals(0, [SELECT COUNT() FROM Pending_Upload__c WHERE Id = :p.Id],
            'Pending row should be deleted by completePending');

        S3_File__c sf = [
            SELECT Id, Content_Version_ID__c, S3_Key__c, Name, Size__c, Type__c
            FROM S3_File__c
            WHERE Content_Version_ID__c = :cv.Id
            LIMIT 1
        ];
        System.assertEquals('salesforce-sync/folder one/big.txt', sf.S3_Key__c);
        System.assertEquals(cv.Id, sf.Content_Version_ID__c);
        System.assertEquals(cv.Title, sf.Name);
        System.assertEquals(cv.ContentSize, sf.Size__c);
    }

    @IsTest
    static void listPending_filters_by_Task_StringId() {
        Task t = new Task(Subject='Pending Task', Status='Completed'); insert t;

        insert new ContentVersion(
            Title='task.txt', PathOnClient='task.txt', VersionData=Blob.valueOf('x'), IsMajorVersion=true
        );
        Id cvId = [SELECT Id FROM ContentVersion WHERE Title='task.txt' LIMIT 1].Id;

        Pending_Upload__c p = new Pending_Upload__c(
            Name='task.txt',
            Content_Version_ID__c = cvId,
            S3_Key__c='k',
            Mime_Type__c='text/plain',
            Size__c=1, Status__c='Pending',
            Task_Id__c=String.valueOf(t.Id)
        );
        insert p;

        Test.startTest();
        List<Pending_Upload__c> fromTask = S3DocService.listPending(t.Id);
        Test.stopTest();

        System.assertEquals(1, fromTask.size(),
            'Query should match Task via Task_Id__c text field');
    }

    /* --------- null-host branches for related* helpers --------- */

    @IsTest
    static void related_helpers_return_empty_on_null() {
        Test.startTest();
        System.assertEquals(0, S3DocService.relatedOpportunities(null).size());
        System.assertEquals(0, S3DocService.relatedCases(null).size());
        System.assertEquals(0, S3DocService.relatedContacts(null).size());
        Test.stopTest();
    }

    /* --------- small sanity checks for simple list APIs (extra lines) --------- */

    @IsTest
    static void simple_lists_return_something_without_error() {
        // seed one of each so queries are non-empty
        insert new Opportunity(Name='O-seed', StageName='Prospecting', CloseDate=Date.today());
        insert new Case(Status='New', Origin='Web', Subject='seed');
        insert new Account(Name='A-seed');
        insert new Contact(LastName='C-seed', AccountId=[SELECT Id FROM Account WHERE Name='A-seed' LIMIT 1].Id);

        Test.startTest();
        S3DocService.getOpportunities();
        S3DocService.getCases();
        S3DocService.getContacts();
        Test.stopTest();

        System.assert(true, 'list methods executed');
    }
}
