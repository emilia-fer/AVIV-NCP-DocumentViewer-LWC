/* =======================================================================
 *  FileMultipartUploadJobTest.cls
 *  ▸ Covers both the happy path and the abort-on-failure path
 *  ▸ Uses lightweight HttpCalloutMock implementations:
 *      – all S3 calls are faked
 *      – every Range-GET to /VersionData returns a tiny “chunk” (so the test
 *        stays well below heap limits; the job never inspects the size)
 *  ▸ Inserts a ContentVersion > 5 MB so that the queueable always takes the
 *    multipart branch
 *  ------------------------------------------------------------------- */
@IsTest
private class FileMultipartUploadJobTest {

    /* ---------------------------------------------------------------
     *  Produce a blob   5 MB + 1 KB   (just over the single-PUT limit)
     *  – Cheap to build: one big String join → Blob
     * ------------------------------------------------------------- */
    private static Blob makeLargeBlob() {
        Integer target = 5 * 1024 * 1024 + 1024;          // 5 MB + 1 KB
        String  chunk  = '0123456789';                    // 10 bytes
        List<String> parts = new List<String>();

        // 100 kB helper chunk
        String chunk100k = '';
        for (Integer i = 0; i < 10000; i++) chunk100k += chunk; // 100 kB

        Integer full = target / chunk100k.length();             // ≈ 52–53
        for (Integer i = 0; i < full; i++)     parts.add(chunk100k);

        Integer rem = target - full * chunk100k.length();
        if (rem > 0) parts.add(chunk100k.substring(0, rem));

        return Blob.valueOf(String.join(parts, ''));
    }

    /* ---------------------------------------------------------------
     *  Insert a ContentVersion (> 5 MB) and return it
     * ------------------------------------------------------------- */
    private static ContentVersion createLargeCV() {
        insert new ContentVersion(
            Title          = 'bigUnitFile.txt',
            PathOnClient   = 'bigUnitFile.txt',
            VersionData    = makeLargeBlob(),
            IsMajorVersion = true
        );
        return [SELECT Id, VersionNumber
                FROM   ContentVersion
                WHERE  Title = 'bigUnitFile.txt'
                LIMIT  1];
    }

    /* ===============================================================
     *  ☑ MOCK 1 – every callout succeeds
     * ============================================================= */
    private class MockOk implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String url = req.getEndpoint();

            // 1️⃣ INIT  POST …?uploads
            if (url.endsWith('?uploads')) {
                res.setStatusCode(200);
                res.setBody(
                    '<InitiateMultipartUploadResult><UploadId>ID123</UploadId></InitiateMultipartUploadResult>'
                );
                return res;
            }
            // 2️⃣ Range GET  /VersionData
            if (url.contains('/VersionData')) {
                res.setStatusCode(206);               // Partial Content
                res.setBody('abc');                   // tiny fake chunk
                return res;
            }
            // 3️⃣ PUT part
            if (url.contains('partNumber=')) {
                // extract part number just to forge an ETag
                String pn = url.substring(url.indexOf('partNumber=') + 11)
                              .split('&')[0];
                res.setStatusCode(200);
                res.setHeader('ETag', 'etag-' + pn);
                return res;
            }
            // 4️⃣ COMPLETE  POST …?uploadId=
            if (url.contains('?uploadId=')) {
                res.setStatusCode(200);
                res.setBody('OK');
                return res;
            }
            // default fallback
            res.setStatusCode(200);
            return res;
        }
    }

    /* ===============================================================
     *  ☒ MOCK 2 – second part PUT fails → triggers abort()
     *    We flag whether the DELETE (/abort) is called.
     * ============================================================= */
    private class MockPartFail implements HttpCalloutMock {

        public Boolean abortSeen = false;

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String url = req.getEndpoint();

            if (url.endsWith('?uploads')) {                       // INIT
                res.setStatusCode(200);
                res.setBody('<InitiateMultipartUploadResult><UploadId>FAIL99</UploadId></InitiateMultipartUploadResult>');
                return res;
            }
            if (url.contains('/VersionData')) {                   // GET chunk
                res.setStatusCode(206);
                res.setBody('abc');
                return res;
            }
            if (url.contains('partNumber=1')) {                   // first PUT OK
                res.setStatusCode(200);
                res.setHeader('ETag', 'etag-1');
                return res;
            }
            if (url.contains('partNumber=2')) {                   // second PUT FAIL
                res.setStatusCode(500);
                res.setBody('server error');
                return res;
            }
            if (req.getMethod() == 'DELETE') {                    // abort()
                abortSeen = true;
                res.setStatusCode(204);
                return res;
            }
            res.setStatusCode(200);
            return res;
        }
    }

    /* ===============================================================
     *  ✅ Happy path
     * ============================================================= */
    @IsTest
    static void multipartSuccess() {

        Test.setMock(HttpCalloutMock.class, new MockOk());

        ContentVersion cv = createLargeCV();
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        Test.startTest();
            Id jobId = System.enqueueJob(
                new FileMultipartUploadJob(cv.Id, key, 'text/plain'));
        Test.stopTest();

        AsyncApexJob j = [
            SELECT Status, NumberOfErrors
            FROM   AsyncApexJob
            WHERE  Id = :jobId
        ];
        System.assertEquals('Completed',   j.Status,
            'Job should succeed when all parts upload');
        System.assertEquals(0, j.NumberOfErrors);
    }

    /* ===============================================================
     *  ❌ Part upload fails → job aborts upload and reports failure
     * ============================================================= */
    @IsTest
    static void multipartAbortOnFailure() {

        MockPartFail mock = new MockPartFail();
        Test.setMock(HttpCalloutMock.class, mock);

        ContentVersion cv = createLargeCV();
        String key = 'salesforce-sync/' + cv.Id + '-v' + cv.VersionNumber + '.txt';

        Test.startTest();
        Id jobId = System.enqueueJob(new FileMultipartUploadJob(cv.Id, key, 'text/plain'));
        try {
            Test.stopTest();
            System.assert(false, 'Expected UploadException');
        } catch (FileMultipartUploadJob.UploadException e) {
            // expected
        }

        AsyncApexJob j = [
            SELECT Status
            FROM   AsyncApexJob
            WHERE  Id = :jobId
        ];
        System.assertEquals('Failed', j.Status,
            'Job should fail when a part upload returns 500');
        System.assertEquals(true, mock.abortSeen,
            'Multipart upload must be aborted on error');
    }
}