@isTest
private class ObjectAddTest {
    // Simple mock that returns status 200
    class S3Mock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/plain');
            res.setBody('OK');
            res.setStatusCode(200);
            return res;
        }
    }
    
    @isTest
    static void testUploadFileToS3() {
        Test.setMock(HttpCalloutMock.class, new S3Mock());
        Test.startTest();
        Integer status = ObjectAdd.uploadFileToS3();
        Test.stopTest();
        System.assertEquals(200, status, 'Expected status code 200 from S3 mock');
    }
}