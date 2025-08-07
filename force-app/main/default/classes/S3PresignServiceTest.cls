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

}