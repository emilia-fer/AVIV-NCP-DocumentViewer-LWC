/* ======================================================================= *
 *  FileUploadJob – direct-PUT for small files, defer record for big ones  *
 * ======================================================================= */
public with sharing class FileUploadJob implements Queueable, Database.AllowsCallouts {

    /* ---------- tweakables ---------- */
    private static final Long   MAX_DIRECT_BYTES = 6L * 1024L * 1024L; // 6 MB
    private static final String S3_NC            = 'AWS_S3';           // Named Credential
    private static final Integer TIMEOUT         = 30000;              // 30 s

    /* ---------- state from caller ---------- */
    private final Id     cvId;
    private final String s3Key;
    private final String mimeType;

    private final Id     accountId;
    private final Id     opportunityId;
    private final Id     caseId;
    private final Id     contactId;
    private final String taskId; // plain text

    public FileUploadJob(
        Id contentVersionId,
        String targetS3Key,
        String mime,
        Id accountId,
        Id opportunityId,
        Id caseId,
        Id contactId,
        String taskId
    ){
        this.cvId          = contentVersionId;
        this.s3Key         = targetS3Key;
        this.mimeType      = mime;
        this.accountId     = accountId;
        this.opportunityId = opportunityId;
        this.caseId        = caseId;
        this.contactId     = contactId;
        this.taskId        = taskId;
    }

    /* Encode each path segment but preserve slashes — avoids %2F in S3 key */
    private static String encodeS3Key(String key) {
        if (String.isBlank(key)) return '';
        List<String> parts = key.split('/');
        for (Integer i=0; i<parts.size(); i++) {
            String seg = EncodingUtil.urlEncode(parts[i], 'UTF-8');
            // Salesforce urlEncode uses '+' for spaces; canonical path wants %20
            seg = seg != null ? seg.replace('+','%20') : '';
            parts[i] = seg;
        }
        return String.join(parts, '/');
    }

    private static String truncate(String s, Integer max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max) + '…';
    }

    /* =================================================================== */
    public void execute(QueueableContext qc){

        ContentVersion cv = [
            SELECT Id, VersionData, ContentSize
            FROM   ContentVersion
            WHERE  Id = :cvId
        ];

        // 1) Small files → direct PUT
        if (cv.ContentSize <= MAX_DIRECT_BYTES){
            final String endpoint = 'callout:' + S3_NC + '/' + encodeS3Key(s3Key);
            final String ct = String.isBlank(mimeType) ? 'application/octet-stream' : mimeType;

            System.debug(LoggingLevel.INFO,
                'FileUploadJob: small-file PUT → ' + endpoint +
                ' | size=' + cv.ContentSize + ' | ct=' + ct
            );

            HttpRequest put = new HttpRequest();
            put.setMethod('PUT');
            put.setEndpoint(endpoint);
            put.setHeader('Content-Type', ct);
            put.setTimeout(TIMEOUT);
            put.setBodyAsBlob(cv.VersionData);

            try {
                HttpResponse res = new Http().send(put);

                Integer code = res.getStatusCode();
                String  stat = res.getStatus();
                String  body = truncate(res.getBody(), 500);

                System.debug(LoggingLevel.INFO,
                    'FileUploadJob: PUT response code=' + code + ' status=' + stat + ' body=' + body
                );

                if (code != 200) {
                    // Make the error highly actionable
                    throw new UploadException(
                        'Direct PUT failed – code=' + code +
                        ', status=' + (stat == null ? '' : stat) +
                        ', body=' + (body == null ? '' : body)
                    );
                }
                System.debug('✅ File ' + s3Key + ' uploaded directly (' + cv.ContentSize + ' bytes)');
                return;

            } catch (Exception e) {
                // Surface callout problems (DNS, auth, SigV4, etc.)
                System.debug(LoggingLevel.ERROR,
                    'FileUploadJob: callout exception: ' + e.getMessage()
                );
                throw new UploadException('Direct PUT callout failed – ' + e.getMessage());
            }
        }

        // 2) Bigger files → create Pending_Upload__c
        Pending_Upload__c p = new Pending_Upload__c(
            Name                   = s3Key,
            Content_Version_ID__c  = cv.Id,
            S3_Key__c              = s3Key,
            Mime_Type__c           = String.isBlank(mimeType) ? 'application/octet-stream' : mimeType,
            Size__c                = cv.ContentSize,
            Status__c              = 'Pending',
            Account_ID__c          = accountId,
            Opportunity_ID__c      = opportunityId,
            Case_ID__c             = caseId,
            Contact_ID__c          = contactId,
            Task_Id__c             = taskId
        );
        insert p;

        System.debug('➕ Deferred big file – Pending_Upload__c Id ' + p.Id);
    }

    public class UploadException extends Exception{}
}