/*
 *  FileMultipartUploadJobTest.cls   (minimal stub)
 *  ------------------------------------------------
 *  The old multipart-upload logic has been retired.  This placeholder
 *  keeps the class name present so the repository still compiles,
 *  but it no longer asserts on multipart behaviour.
 *
 *  It enqueues the job with a tiny (1 kB) ContentVersion so that the
 *  “small-file” code path runs and completes successfully.
 */

@IsTest
private class FileMultipartUploadJobTest {

    @IsTest
    static void enqueueSmallFile_ok() {
        // ── create a 1 kB dummy ContentVersion ───────────────────────
        Blob tinyBlob   = Blob.valueOf('x'.repeat(1024));
        ContentVersion cv = new ContentVersion(
            Title          = 'tiny.txt',
            PathOnClient   = 'tiny.txt',
            VersionData    = tinyBlob,
            IsMajorVersion = true
        );
        insert cv;

        // ── run the queueable (small-file branch) ────────────────────
        Test.startTest();
        Id jobId = System.enqueueJob(
            new FileMultipartUploadJob(
                cv.Id,
                'salesforce-sync/' + cv.Id + '.txt',
                'text/plain'
            )
        );
        Test.stopTest();

        // ── verify the job completed without errors ──────────────────
        AsyncApexJob j = [
            SELECT Status, NumberOfErrors
            FROM   AsyncApexJob
            WHERE  Id = :jobId
        ];
        System.assertEquals('Completed', j.Status,
            'Queueable should finish successfully for a small file');
        System.assertEquals(0, j.NumberOfErrors);
    }
}
