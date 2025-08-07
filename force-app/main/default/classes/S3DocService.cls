public with sharing class S3DocService {

    @AuraEnabled(cacheable=true)
    public static List<Map<String,Object>> getDocs(Id recordId) {

        /* 1.  grab the files (current query) ------------------------------ */
        List<S3_File__c> files = [
            SELECT Id, Name, Type__c, Size__c, S3_Key__c,
                   Creation_Date__c, Description__c,
                   Account_ID__c, Opportunity_ID__c,
                   Task_ID__c, Opportunity_ID__r.Name,
    			   Case_ID__c, Case_ID__r.CaseNumber, Contact_ID__c,
   				   Contact_ID__r.Name
            FROM   S3_File__c
            WHERE  (Account_ID__c     = :recordId OR
                    Opportunity_ID__c = :recordId OR
                    Contact_ID__c     = :recordId OR
                    Case_ID__c        = :recordId OR
                    Task_ID__c        = :recordId)
        ];

        /* 2.  collect Task-Ids and fetch their Subjects ------------------- */
        Set<Id> taskIds = new Set<Id>();
        for (S3_File__c f : files) if (f.Task_ID__c != null) taskIds.add((Id)f.Task_ID__c);

        Map<Id, String> taskSubjects = new Map<Id, String>();
        if (!taskIds.isEmpty()) {
            for (Task t : [SELECT Id, Subject FROM Task WHERE Id IN :taskIds]) {
                taskSubjects.put(t.Id, t.Subject);
            }
        }

        /* 3.  flatten everything into a Map<String,Object> for LWC -------- */
        List<Map<String,Object>> out = new List<Map<String,Object>>();
        for (S3_File__c f : files) {
            Map<String,Object> row = (Map<String,Object>)JSON.deserializeUntyped(JSON.serialize(f));

            Id tid = (Id)f.Task_ID__c;
            if (tid != null) {
                row.put('TaskUrl',   '/'+tid);
                row.put('TaskName',  taskSubjects.get(tid) != null
                                     ? taskSubjects.get(tid)
                                     : String.valueOf(tid));     // fallback
            }
            out.add(row);
        }
        return out;
    }

    /* ---------- get the file’s binary content + MIME type ---------- */
    public class FilePayload {
        @AuraEnabled public String base64Data;
        @AuraEnabled public String contentType;
    }
    
	// URL‑encode only the *individual* segments, then re‑join with “/”
    private static String encodeKeyPreservingSlashes(String key) {
        List<String> parts = key.split('/');
        for (Integer i = 0; i < parts.size(); i++) {
            // encode each segment, keep spaces as %20
            parts[i] = EncodingUtil.urlEncode(parts[i], 'UTF‑8')
                                   .replace('+','%20');
        }
        return String.join(parts, '/');
    }
    
    @AuraEnabled
    public static FilePayload getFile(String s3Key) {
        System.debug('Fetching S3 object with key: ' + s3Key);
        if (String.isBlank(s3Key)) {
            throw new AuraHandledException('Missing S3 key!');
        }
        HttpRequest req = new HttpRequest();
        String encodedKey = encodeKeyPreservingSlashes(s3Key); 
        req.setEndpoint('callout:AWS_S3/' + encodedKey);
        req.setMethod('GET');
    
        HttpResponse res = (new Http()).send(req);
    
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'S3 returned ' + res.getStatus() + ' for ' + s3Key);
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

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunities() {
        return [SELECT Id, Name FROM Opportunity ORDER BY Name LIMIT 100];
    }
    @AuraEnabled(cacheable=true)
    public static List<Case> getCases() {
        return [SELECT Id, CaseNumber FROM Case ORDER BY CreatedDate DESC LIMIT 100];
    }
    @AuraEnabled(cacheable=true)
    public static List<Contact> getContacts() {
        return [SELECT Id, Name FROM Contact ORDER BY Name LIMIT 100];
    }

	@AuraEnabled(cacheable=true)
    public static List<Opportunity> relatedOpportunities(Id hostId) {
        if (hostId == null) return new List<Opportunity>();
    
        String prefix = String.valueOf(hostId).substring(0,3);
        if (prefix == '001') { // Account page
            return [SELECT Id, Name
                    FROM   Opportunity
                    WHERE  AccountId = :hostId
                    ORDER  BY CloseDate DESC, LastModifiedDate DESC
                    LIMIT  200];
        } else if (prefix == '500') { // Case page
            // From Case → its ParentId is the Account (if set)
            Id acct = [SELECT AccountId FROM Case WHERE Id = :hostId].AccountId;
            if (acct == null) return new List<Opportunity>();
            return [SELECT Id, Name
                    FROM   Opportunity
                    WHERE  AccountId = :acct
                    ORDER  BY CloseDate DESC, LastModifiedDate DESC
                    LIMIT  200];
        }
        // other pages (Opportunity / Contact): no opp lookup
        return new List<Opportunity>();
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Case> relatedCases(Id hostId) {
        if (hostId == null) return new List<Case>();
        String prefix = String.valueOf(hostId).substring(0,3);
    
        if (prefix == '001') {          // Account → its cases
            return [SELECT Id, CaseNumber
                    FROM   Case
                    WHERE  AccountId = :hostId
                    ORDER  BY CreatedDate DESC
                    LIMIT  200];
        } else if (prefix == '003') {   // Contact page
            return [SELECT Id, CaseNumber
                    FROM   Case
                    WHERE  ContactId = :hostId
                    ORDER  BY CreatedDate DESC
                    LIMIT  200];
        }
        return new List<Case>();        // Account / Case pages handled above
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Contact> relatedContacts(Id hostId) {
        if (hostId == null) return new List<Contact>();
        String prefix = String.valueOf(hostId).substring(0,3);
    
        if (prefix == '001') { // Account only
            return [SELECT Id, Name
                    FROM   Contact
                    WHERE  AccountId = :hostId
                    ORDER  BY LastModifiedDate DESC
                    LIMIT  200];
        }
        return new List<Contact>();
    }
}