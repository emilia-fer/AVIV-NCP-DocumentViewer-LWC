/**
 *  Handles ONE ContentVersion:
 *   • decides whether upload is needed
 *   • PUTs to S3 via Named Credential 'AWS_S3'
 *   • UPSERTS S3_File__c (external id = Content_Version_ID__c)
 *
 *  Uses your fields:
 *   • Content_Version_ID__c  (External Id, Text(18))
 *   • Content_Modified__c    (DateTime  – mirrors CV.LastModifiedDate)
 *   • Last_Synched__c        (DateTime  – when upload succeeded)
 */
public with sharing class FileSyncWorker {

    // ---------- CONFIG -------------------------------------------------
    private static final String NC  = 'AWS_S3';            // Named Credential
    private static final String DIR = 'salesforce-sync/';  // folder prefix in S3
    private static final Integer TIMEOUT_MS = 30000;

     /* PUTs to S3 and *returns* the S3_File__c ready for upsert,
     * or NULL when nothing changed.
     */
    /* inside FileSyncWorker.cls  ------------------------------------------- */
    
    public static S3_File__c sync(ContentVersion cv,
                                  Map<String,S3_File__c> existingMap){
    
        S3_File__c existing = existingMap.get((String)cv.Id);
    
        // --- 1. already up-to-date? ---------------------------------------
        if (existing != null &&
            existing.Content_Modified__c != null &&
            cv.LastModifiedDate <= existing.Content_Modified__c){
            return null;
        }
    
        // --- 2. build human-readable S3 key ----------------------------------
        String ext       = (cv.FileExtension == null ? '' : cv.FileExtension.toLowerCase());
        String baseTitle = String.isBlank(cv.Title) ? 'file' : cv.Title;
        
        // keep it S3-safe and reasonably short
        String safeTitle = baseTitle.replaceAll('[^A-Za-z0-9._-]+','_').left(120);
        
        // human-readable but still unique per version
        String key = DIR
                   + safeTitle
                   + '-v' + cv.VersionNumber
                   + (String.isBlank(ext) ? '' : '.' + ext);
        
    
        Blob body = [SELECT VersionData FROM ContentVersion WHERE Id = :cv.Id].VersionData;
        singlePut(key, body, cv.FileExtension);

        /* --- 3.  prepare S3_File__c for upsert --------------------------- */
        S3_File__c up = existing == null ? new S3_File__c()
                                         : existing.clone(false, true, true, true);
        up.Content_Version_ID__c = cv.Id;
        up.Name                  = cv.Title;
        up.Size__c               = cv.ContentSize;
        up.Type__c               = cv.FileType;
        up.Content_Modified__c   = cv.LastModifiedDate;
        up.Last_Synched__c       = System.now();
        up.S3_Key__c             = key;
    
        return up;
    }
    
    /* ------------ helper: single PUT (≤ 5 MB) ---------------------------- */
    private static void singlePut(String key, Blob body, String ext){
    
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NC + '/' + key);
        req.setMethod('PUT');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', mime(ext));
        req.setBodyAsBlob(body);
    
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200){
            throw new FileSyncException(
                'S3 PUT failed (' + res.getStatus() + ') for ' + key);
        }
    }

    
    /* helper – minimal MIME lookup */
    private static String mime(String ext){
        ext = (ext==null?'':ext.toLowerCase());
        if (ext=='png')  return 'image/png';
        if (ext=='jpg'||ext=='jpeg') return 'image/jpeg';
        if (ext=='pdf')  return 'application/pdf';
        if (ext=='gif')  return 'image/gif';
        if (ext=='docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (ext=='msg')  return 'application/vnd.ms-outlook';
        if (ext=='eml')  return 'message/rfc822';
        return 'application/octet-stream';
    }



    public class FileSyncException extends Exception{}
}