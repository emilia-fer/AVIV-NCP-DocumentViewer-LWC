public with sharing class ObjectList {
    public class S3ObjectInfo {
        public String key;
        public String lastModified;
        public String storageClass;
        public S3ObjectInfo(String key, String lastModified, String storageClass) {
            this.key = key;
            this.lastModified = lastModified;
            this.storageClass = storageClass;
        }
    }

    @AuraEnabled
    public static List<S3ObjectInfo> listObjects() {
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint('callout:AWS_S3/'); 

        Http http = new Http();
        HttpResponse res = http.send(request);

        System.assertEquals(200, res.getStatusCode(), 'S3 did not return 200');

        String namespace = 'http://s3.amazonaws.com/doc/2006-03-01/';
        Dom.Document doc = res.getBodyDocument();
        Dom.XMLNode root = doc.getRootElement();

        String bucketName = root.getChildElement('Name', namespace) != null
            ? root.getChildElement('Name', namespace).getText()
            : null;

        System.debug('Bucket Name: ' + bucketName);
        System.debug('The following objects are stored in the bucket: ');

        List<S3ObjectInfo> result = new List<S3ObjectInfo>();

        for (Dom.XMLNode node : root.getChildElements()) {
            if (node.getName() == 'Contents' && node.getNamespace() == namespace) {
                String key = node.getChildElement('Key', namespace) != null ?
                             node.getChildElement('Key', namespace).getText() : null;
                String lastModified = node.getChildElement('LastModified', namespace) != null ?
                             node.getChildElement('LastModified', namespace).getText() : null;
                String storageClass = node.getChildElement('StorageClass', namespace) != null ?
                             node.getChildElement('StorageClass', namespace).getText() : null;

                System.debug('Key: ' + key);
                System.debug('StorageClass: ' + storageClass);
                System.debug('LastModified: ' + lastModified);

                result.add(new S3ObjectInfo(key, lastModified, storageClass));
            }
        }
        return result;
    }
}