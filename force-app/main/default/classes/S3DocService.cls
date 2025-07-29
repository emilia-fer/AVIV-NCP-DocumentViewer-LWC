public with sharing class S3DocService {

    /* ---------- list files for the table ---------- */
    @AuraEnabled(cacheable=true)
    public static List<S3_File__c> getDocs(Id recordId) {
        return [
            SELECT Id, Name, Size__c, Type__c, Creation_Year__c, Description__c,
       		Account_ID__r.Name, Opportunity_ID__r.Name, Case_ID__r.CaseNumber,
       		Contact_ID__r.Name
            FROM   S3_File__c
            WHERE  Record_ID__c = :recordId OR Account_ID__c = :recordId OR Case_ID__c = :recordId
            OR Opportunity_ID__c = :recordId OR Contact_ID__c = :recordId
            ORDER  BY Name
        ];
    }

    /* ---------- get the file’s binary content + MIME type ---------- */
    public class FilePayload {
        @AuraEnabled public String base64Data;
        @AuraEnabled public String contentType;
    }

    @AuraEnabled
    public static FilePayload getFile(String fileName) {
        HttpRequest req = new HttpRequest();
        String encodedKey = EncodingUtil.urlEncode(fileName, 'UTF-8')
                                         .replace('+', '%20');
        req.setEndpoint('callout:AWS_S3/' + encodedKey);
        req.setMethod('GET');
    
        HttpResponse res = (new Http()).send(req);
    
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'S3 returned ' + res.getStatus() + ' for ' + fileName);
        }
        Blob body     = res.getBodyAsBlob();
        String mime   = res.getHeader('Content-Type');
        FilePayload p = new FilePayload();
        p.base64Data  = EncodingUtil.base64Encode(body);
        p.contentType = String.isBlank(mime) ? 'application/octet-stream' : mime;
        return p;
    }
    
    /* ---------- update Description only ---------- */
    @AuraEnabled
    public static void updateDescriptions(List<S3_File__c> files) {
        // whitelist: only Description__c may change
        List<S3_File__c> updates = new List<S3_File__c>();
        for (S3_File__c f : files) {
            updates.add(new S3_File__c(
                Id = f.Id,
                Description__c = f.Description__c
            ));
        }
        update updates;
    }


}