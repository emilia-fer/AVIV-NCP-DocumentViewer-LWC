public with sharing class ObjectAdd {
    @AuraEnabled
    public static Integer uploadFileToS3() {
        String fileNameToCreate = 'BytesInTheCloud.txt';
        String fileContent = 'Greetings from the cloud! Your data is safe and sound in S3.';
        
        System.debug('Preparing to upload file: ' + fileNameToCreate);
        System.debug('File content: ' + fileContent);
        
        HttpRequest request = new HttpRequest();
        request.setMethod('PUT');
        request.setBody(fileContent);
        request.setEndpoint('callout:AWS_S3/' + fileNameToCreate);

        System.debug('HttpRequest prepared:');
        System.debug('  Method: ' + request.getMethod());
        System.debug('  Endpoint: ' + request.getEndpoint());
        System.debug('  Body: ' + request.getBody());
        
        Http http = new Http();
        System.debug('Sending HTTP request to S3...');
        HttpResponse res = http.send(request);

        System.debug('Received response from S3:');
        System.debug('  Status code: ' + res.getStatusCode());
        System.debug('  Body: ' + res.getBody());

        // Return status code for verification
        return res.getStatusCode();
    }
}