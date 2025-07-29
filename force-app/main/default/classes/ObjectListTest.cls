@isTest
private class ObjectListTest {
    // Mock HTTP callout to return sample S3 XML
    class S3MockResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/xml');
            res.setStatusCode(200);
            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                '<Name>testbucket</Name>' +
                '<Contents>' +
                    '<Key>example1.txt</Key>' +
                    '<LastModified>2024-07-08T11:00:00.000Z</LastModified>' +
                    '<StorageClass>STANDARD</StorageClass>' +
                '</Contents>' +
                '<Contents>' +
                    '<Key>example2.txt</Key>' +
                    '<LastModified>2024-07-07T09:30:00.000Z</LastModified>' +
                    '<StorageClass>GLACIER</StorageClass>' +
                '</Contents>' +
                '</ListBucketResult>'
            );
            return res;
        }
    }

    @isTest
    static void testListObjects() {
        Test.setMock(HttpCalloutMock.class, new S3MockResponse());
        Test.startTest();
        List<ObjectList.S3ObjectInfo> objs = ObjectList.listObjects();
        Test.stopTest();

        System.assertEquals(2, objs.size(), 'Should parse two S3 objects');

        // Check first object
        System.assertEquals('example1.txt', objs[0].key);
        System.assertEquals('2024-07-08T11:00:00.000Z', objs[0].lastModified);
        System.assertEquals('STANDARD', objs[0].storageClass);

        // Check second object
        System.assertEquals('example2.txt', objs[1].key);
        System.assertEquals('2024-07-07T09:30:00.000Z', objs[1].lastModified);
        System.assertEquals('GLACIER', objs[1].storageClass);
    }
}