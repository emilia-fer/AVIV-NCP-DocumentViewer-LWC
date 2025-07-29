@IsTest
private class MsgPreviewServiceTest {
    @IsTest static void callout() {
        // Minimal fake
        Test.setMock(HttpCalloutMock.class, new MockOk());
        String body = MsgPreviewService.fetch('dummy.msg');
        System.assertEquals('{"ok":"yes"}', body);
    }
    class MockOk implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setBody('{"ok":"yes"}');
            return r;
        }
    }
}