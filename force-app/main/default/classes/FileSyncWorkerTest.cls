@IsTest
private class FileSyncWorkerTest {

    /* ----------------------- helpers ----------------------- */

    // ~100 KB blob (safe, fast)
    private static Blob smallBlob() {
        String ten = '0123456789'; // 10 bytes
        String chunk = '';
        for (Integer i = 0; i < 10000; i++) chunk += ten; // ≈100 KB
        return Blob.valueOf(chunk);
    }

    // Create a ContentVersion and return it (queried with key fields)
    private static ContentVersion makeCV(String name, Blob body){
        insert new ContentVersion(
            Title          = name,
            PathOnClient   = name,
            VersionData    = body,
            IsMajorVersion = true
        );
        return [
            SELECT Id, Title, VersionNumber, FileExtension, FileType,
                   ContentSize, LastModifiedDate, ContentDocumentId
            FROM   ContentVersion
            WHERE  Title = :name
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    // Attach a CV to various records via ContentDocumentLink
    private static void linkCvToEntities(ContentVersion cv,
                                         Id accountId,
                                         Id oppId,
                                         Id caseId,
                                         Id contactId,
                                         Id taskId) {
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        if (accountId  != null) links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = accountId,  ShareType = 'V'));
        if (oppId      != null) links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = oppId,      ShareType = 'V'));
        if (caseId     != null) links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = caseId,     ShareType = 'V'));
        if (contactId  != null) links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = contactId,  ShareType = 'V'));
        if (taskId     != null) links.add(new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, LinkedEntityId = taskId,     ShareType = 'V'));
        insert links;
    }

    /* --------- HTTP mock that captures request info (200 OK) --------- */
    private class Capture200 implements HttpCalloutMock {
        Integer callCount = 0;
        String  lastEndpoint;
        String  lastContentType;
        public HTTPResponse respond(HTTPRequest req){
            callCount++;
            lastEndpoint    = req.getEndpoint();
            lastContentType = req.getHeader('Content-Type');
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setStatus('OK');
            r.setBody('OK');
            return r;
        }
    }

    /* ----------------------- TESTS ------------------------- */

    @IsTest
    static void smallFile_uploads_and_returns_S3File() {
        // Arrange (DML before any callouts)
        ContentVersion cv = makeCV('photo.PNG', smallBlob());

        // Act – callout path
        Capture200 mock = new Capture200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3_File__c up = FileSyncWorker.sync(cv, new Map<String,S3_File__c>());
        Test.stopTest();

        // Assert – upload happened, object to upsert is populated
        System.assertEquals(1, mock.callCount, 'should PUT once');
        System.assertNotEquals(null, up, 'should return S3_File__c to upsert');
        System.assertNotEquals(null, up.S3_Key__c, 'key should be set');
        System.assert(up.S3_Key__c.startsWith('salesforce-sync/'), 'key should have DIR prefix');
        System.assert(up.S3_Key__c.endsWith('.png'), 'extension should be normalized to lowercase .png');

        // Content-Type derived from extension (PNG)
        System.assertEquals('image/png', mock.lastContentType, 'PNG should map to image/png');
    }

    @IsTest
    static void skip_when_existing_is_up_to_date() {
        ContentVersion cv = makeCV('doc.txt', Blob.valueOf('abc'));

        // existing S3 record that is already up-to-date
        S3_File__c existing = new S3_File__c(
            Content_Version_ID__c = cv.Id,
            Content_Modified__c   = cv.LastModifiedDate,
            Last_Synched__c       = System.now(),
            Name                  = cv.Title,
            S3_Key__c             = 'anything'
        );

        // No callouts should happen in skip branch
        Capture200 mock = new Capture200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3_File__c result = FileSyncWorker.sync(cv, new Map<String,S3_File__c>{
            (String)cv.Id => existing
        });
        Test.stopTest();

        System.assertEquals(null, result, 'up-to-date → return null');
        System.assertEquals(0, mock.callCount, 'skip branch must not call out');
    }

    @IsTest
    static void bigFile_creates_PendingUpload_and_sets_related_refs() {
        // Force the "big" branch by lowering the threshold temporarily
        Long original = FileSyncWorker.MAX_DIRECT_BYTES;
        try {
            FileSyncWorker.MAX_DIRECT_BYTES = 1024; // 1 KB

            // Seed related records to be discovered via ContentDocumentLink
            Account    a  = new Account(Name = 'Acme');
            insert a;
            Opportunity o = new Opportunity(
                Name = 'Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(10), AccountId = a.Id
            );
            insert o;
            Contact   c   = new Contact(LastName = 'Smith', AccountId = a.Id);
            insert c;
            Case      cs  = new Case(Subject = 'Case A', AccountId = a.Id);
            insert cs;
            Task      t   = new Task(Subject = 'Follow up', Status = 'Not Started', Priority = 'Normal');
            insert t;

            // Create a ~100KB CV (so > 1KB threshold)
            ContentVersion cv = makeCV('big one.PDF', smallBlob());

            // Link the CV to all the above records
            linkCvToEntities(cv, a.Id, o.Id, cs.Id, c.Id, t.Id);

            // Act – big branch does NOT perform callouts (only DML)
            Test.startTest();
            S3_File__c result = FileSyncWorker.sync(cv, new Map<String,S3_File__c>());
            Test.stopTest();

            // Assert – result is null (no S3_File__c upsert), but a Pending_Upload__c row exists
            System.assertEquals(null, result, 'big file → returns null and defers');
            Pending_Upload__c p = [
                SELECT Id, Name, S3_Key__c, Mime_Type__c, Size__c, Status__c,
                       Account_ID__c, Opportunity_ID__c, Case_ID__c, Contact_ID__c, Task_Id__c,
                       Content_Version_ID__c
                FROM   Pending_Upload__c
                WHERE  Content_Version_ID__c = :cv.Id
                LIMIT 1
            ];

            System.assertEquals('Pending', p.Status__c);
            System.assertEquals(cv.Id,     p.Content_Version_ID__c);
            System.assert(p.S3_Key__c.startsWith('salesforce-sync/'),
                          'key should carry DIR prefix');
            System.assert(p.S3_Key__c.endsWith('.pdf'),
                          'mime/ext should reflect sanitized extension');
            System.assertEquals('application/pdf', p.Mime_Type__c);
            System.assertEquals(cv.ContentSize, p.Size__c);

            // Related refs resolved by findRelated(ContentVersionId)
            System.assertEquals(a.Id,  p.Account_ID__c);
            System.assertEquals(o.Id,  p.Opportunity_ID__c);
            System.assertEquals(cs.Id, p.Case_ID__c);
            System.assertEquals(c.Id,  p.Contact_ID__c);
            System.assertEquals((String)t.Id, p.Task_Id__c);

        } finally {
            FileSyncWorker.MAX_DIRECT_BYTES = original;
        }
    }

    @IsTest
    static void key_sanitization_and_no_extension() {
        // Title with spaces/emoji and NO extension exercises the sanitizer
        ContentVersion cv = makeCV('Weird 🧪 Name', smallBlob());

        Capture200 mock = new Capture200();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        S3_File__c up = FileSyncWorker.sync(cv, new Map<String,S3_File__c>());
        Test.stopTest();

        System.assertEquals(1, mock.callCount);

        // No extension appended when cv.FileExtension is null/blank
        System.assertEquals(-1, up.S3_Key__c.lastIndexOf('.'),
            'no extension → key should not contain a dot/ext');

        // The sanitizer collapses runs of invalid chars to ONE underscore
        System.assert(
            up.S3_Key__c.startsWith('salesforce-sync/Weird_Name'),
            'sanitized key should start with safe title, got: ' + up.S3_Key__c
        );

        System.assert(up.S3_Key__c.contains('-v' + cv.VersionNumber),
            'key should include version suffix, got: ' + up.S3_Key__c);
    }
}
