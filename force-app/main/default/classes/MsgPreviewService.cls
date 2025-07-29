// MsgPreviewService.cls
// API call is server‑side so no CORS
public with sharing class MsgPreviewService {
    @AuraEnabled(cacheable=false)
    public static String fetch(String key) {
        if (String.isBlank(key)) {
            throw new AuraHandledException('Key is required');
        }
        String url = 'callout:MsgPreviewAPI/convert'
                   + '?bucket=avivdocdev'
                   + '&key=' + EncodingUtil.urlEncode(key,'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');

        Http http   = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('API error: ' + res.getBody());
        }
        return res.getBody(); // JSON string
    }
}