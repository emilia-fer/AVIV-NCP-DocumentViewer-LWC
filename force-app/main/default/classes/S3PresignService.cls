public with sharing class S3PresignService {

    @AuraEnabled(cacheable=false)
    public static PresignResponse getPresignedUrl(
        String fileName,
        String contentType,
        Long   fileSize
    ) {
        System.debug('### S3PresignService – param contentType = ' + contentType);

        // ---------- 1.  call Lambda through the Named Credential ----------
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:S3PresignAPI/generate-presigned-url'); // Named Credential
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{
            'fileName'    => fileName,
            'contentType' => contentType,
            'fileSize'    => fileSize
        }));

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('### S3PresignService – status: ' + res.getStatusCode());
        System.debug('### S3PresignService – body  : ' + res.getBody());

        // ---------- 2.  network / HTTP‑level errors ----------
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Upload failed – service returned HTTP ' + res.getStatusCode()
            );
        }

        // ---------- 3.  parse the single‑level JSON ----------
        Map<String,Object> payload =
            (Map<String,Object>) JSON.deserializeUntyped(res.getBody());

        // ---------- 4.  Lambda said “error” ? ----------
        if (payload.containsKey('error')) {
            // propagate the readable reason coming from Lambda
            throw new AuraHandledException(
                'Upload failed – ' + (String) payload.get('error')
            );
        }

        // ---------- 5.  happy path ----------
        String uploadUrl = (String) payload.get('uploadUrl');
        String s3Key     = (String) payload.get('s3Key');

        if (String.isBlank(uploadUrl) || String.isBlank(s3Key)) {
            throw new AuraHandledException(
                'Upload failed – invalid response from service.'
            );
        }
        return new PresignResponse(uploadUrl, s3Key);
    }
    
    @AuraEnabled(cacheable=false)
    public static String getPresignedGetUrl(String s3Key) {
        // 1. Call Lambda through the Named Credential, just like before
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:S3PresignAPI/generate-presigned-get-url');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String,Object>{
            's3Key' => s3Key
        }));
    
        Http http = new Http();
        HttpResponse res = http.send(req);
    
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'Download failed – service returned HTTP ' + res.getStatusCode()
            );
        }
    
        Map<String,Object> payload =
            (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
    
        if (payload.containsKey('error')) {
            throw new AuraHandledException(
                'Download failed – ' + (String) payload.get('error')
            );
        }
    
        String url = (String) payload.get('downloadUrl');
        if (String.isBlank(url)) {
            throw new AuraHandledException('Download failed – invalid response from service.');
        }
        return url;
    }


    // ---------------------------------------------------------------------
    public class PresignResponse {
        @AuraEnabled public String uploadUrl;
        @AuraEnabled public String s3Key;
        public PresignResponse(String url, String key) {
            uploadUrl = url;
            s3Key     = key;
        }
    }
}