@IsTest
public class S3PresignServiceTest {
    // Inner mock class for a successful response
    class MockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockSuccess called: ' + req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            // Dummy payload matching what Apex expects from the API
            res.setBody('{"uploadUrl":"https://example.com/upload","s3Key":"bucket/myfile.txt"}');
            return res;
        }
    }
    // Inner mock class for an error response
    class MockFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockFailure called: ' + req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Something went wrong"}');
            return res;
        }
    }
    // Inner mock class for a successful GET response
    class MockGetSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockGetSuccess called: ' + req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"downloadUrl":"https://example.com/download"}');
            return res;
        }
    }
    // Inner mock class for an error GET response
    class MockGetFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.debug('MockGetFailure called: ' + req.getBody());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Something went wrong"}');
            return res;
        }
    }
    @IsTest
    static void testGetPresignedUrl_Success() {
        // Set mock response to be successful
        Test.setMock(HttpCalloutMock.class, new MockSuccess());
        System.debug('--- Starting testGetPresignedUrl_Success ---');
        Test.startTest();
        S3PresignService.PresignResponse resp = S3PresignService.getPresignedUrl('myfile.txt', 'text/plain', 123L);
        Test.stopTest();
        System.debug('Upload URL: ' + resp.uploadUrl);
        System.debug('S3 Key: ' + resp.s3Key);
        System.assertEquals('https://example.com/upload', resp.uploadUrl, 'UploadUrl mismatch');
        System.assertEquals('bucket/myfile.txt', resp.s3Key, 'S3Key mismatch');
    }
    @IsTest
    static void testGetPresignedUrl_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockFailure());
        System.debug('--- Starting testGetPresignedUrl_Failure ---');
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            S3PresignService.getPresignedUrl('failfile.txt', 'application/pdf', 456L);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            System.debug('Caught AuraHandledException as expected: ' + ex.getMessage());
        }
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Exception was not thrown for failure response');
    }

    @IsTest
    static void testGetPresignedGetUrl_Success() {
        Test.setMock(HttpCalloutMock.class, new MockGetSuccess());
        System.debug('--- Starting testGetPresignedGetUrl_Success ---');
        Test.startTest();
        String url = S3PresignService.getPresignedGetUrl('bucket/myfile.txt');
        Test.stopTest();
        System.assertEquals('https://example.com/download', url, 'DownloadUrl mismatch');
    }

    @IsTest
    static void testGetPresignedGetUrl_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockGetFailure());
        System.debug('--- Starting testGetPresignedGetUrl_Failure ---');
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            S3PresignService.getPresignedGetUrl('bucket/fail.txt');
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
            System.debug('Caught AuraHandledException as expected: ' + ex.getMessage());
        }
        Test.stopTest();
        System.assertEquals(true, exceptionThrown, 'Exception was not thrown for failure response');
    }

}