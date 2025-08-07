/* ===================================================================== *
 *  FileMultipartUploadJob – session-ID version (no JWT, no NamedCred)   *
 *  -------------------------------------------------------------------  *
 *  – Streams a ContentVersion in 5 MB slices (Range-GET) so heap ≤ 5 MB  *
 *  – Uploads each slice as a part of an S3 multipart upload             *
 *  – Works with any file size that Salesforce allows for Content files  *
 *                                                                      *
 *  Prerequisites                                                        *
 *    · Remote Site Setting  “SelfOrg”  → https://<your-mydomain>.my.salesforce.com
 *    · Named Credential     “AWS_S3”   → **unchanged**, SigV4           *
 * ==================================================================== */
public with sharing class FileMultipartUploadJob
       implements Queueable, Database.AllowsCallouts {

    /* ---------------- constants ---------------- */
    private static final String  S3_NC     = 'AWS_S3';
    private static final String  SELF_SITE = 'SelfOrg';           // Remote-Site-Setting
    private static final String  DIR       = 'salesforce-sync/';
    private static final Long    PART_SZ   = 5L * 1024L * 1024L;  // 5 MB
    private static final Integer TIMEOUT   = 30000;

    /* ---------------- state passed in ----------- */
    private final Id     cvId;
    private final String key;          // already includes Title + ext
    private final String mimeType;

    public FileMultipartUploadJob(Id contentVersionId,
                                  String s3Key,
                                  String mime) {
        this.cvId     = contentVersionId;
        this.key      = s3Key;
        this.mimeType = mime;
    }

    /* ================================================================ */
    public void execute(QueueableContext qc) {

        ContentVersion cv = [
            SELECT Id, ContentSize
            FROM   ContentVersion
            WHERE  Id = :cvId
        ];
        Long size = cv.ContentSize;

        /* 1️⃣  Initiate multipart upload on S3 ----------------------- */
        HttpRequest init = new HttpRequest();
        init.setMethod('POST');
        init.setEndpoint('callout:' + S3_NC + '/' + key + '?uploads');
        init.setTimeout(TIMEOUT);

        HttpResponse initRes = new Http().send(init);
        if (initRes.getStatusCode() != 200) {
            throw new UploadException('INIT failed – ' + initRes.getStatus());
        }
        String uploadId = extract(initRes.getBody(), 'UploadId');

        /* 2️⃣  Loop over every 5 MB slice ---------------------------- */
        Integer partNo       = 1;
        List<String> partsXML = new List<String>();

        for (Long start = 0; start < size; start += PART_SZ) {

            Blob chunk = fetchRange(start, Math.min(start + PART_SZ, size) - 1);

            /* ---- PUT this part to S3 -------------------------------- */
            HttpRequest put = new HttpRequest();
            put.setMethod('PUT');
            put.setEndpoint(
                'callout:' + S3_NC + '/' + key +
                '?partNumber=' + partNo +
                '&uploadId='  + EncodingUtil.urlEncode(uploadId, 'UTF-8')
            );
            put.setHeader('Content-Type', mimeType);
            put.setBodyAsBlob(chunk);
            put.setTimeout(TIMEOUT);

            HttpResponse putRes = new Http().send(put);
            if (putRes.getStatusCode() != 200) {
                abort(uploadId);
                throw new UploadException('Part #' + partNo +
                                          ' failed – ' + putRes.getStatus());
            }
            partsXML.add(
                '<Part><PartNumber>' + partNo + '</PartNumber>' +
                '<ETag>' + putRes.getHeader('ETag') + '</ETag></Part>'
            );
            partNo++;
        }

        /* 3️⃣  Complete multipart upload ---------------------------- */
        HttpRequest fin = new HttpRequest();
        fin.setMethod('POST');
        fin.setEndpoint(
            'callout:' + S3_NC + '/' + key +
            '?uploadId=' + EncodingUtil.urlEncode(uploadId,'UTF-8')
        );
        fin.setHeader('Content-Type', 'application/xml');
        fin.setBody('<CompleteMultipartUpload>' +
                    String.join(partsXML, '') +
                    '</CompleteMultipartUpload>');
        fin.setTimeout(TIMEOUT);

        HttpResponse finRes = new Http().send(fin);
        if (finRes.getStatusCode() != 200) {
            abort(uploadId);
            throw new UploadException('COMPLETE failed – ' +
                                      finRes.getStatus());
        }
    }

    /* ---------------------------------------------------------------
     *  Reads a 5 MB slice of VersionData using the current session-id
     * ------------------------------------------------------------- */
    private Blob fetchRange(Long start, Long size) {
        Long stringEnd = Math.min(start + PART_SZ - 1, size - 1);
    
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() +
            '/services/data/v60.0/sobjects/ContentVersion/' + cvId + '/VersionData');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Range', 'bytes=' + start + '-' + stringEnd);
        req.setTimeout(TIMEOUT);
    
        HttpResponse res = new Http().send(req);
    
        System.debug('*** fetchRange status: ' + res.getStatusCode());
        System.debug('*** fetchRange content-length: ' + res.getHeader('Content-Length'));
        System.debug('*** fetchRange headers: ' + res.getHeaderKeys());
        System.debug('*** fetchRange remote URL: ' + req.getEndpoint());
        System.debug('*** fetchRange actual size: ' + res.getBodyAsBlob().size());
    
        if (res.getStatusCode() != 206) {
            throw new UploadException('Range GET failed – ' + res.getStatusCode() +
                ' (expected 206)');
        }
        return res.getBodyAsBlob();
    }



    /* ----------------------------------------------------------------- */
    private void abort(String uploadId) {
        try {
            HttpRequest del = new HttpRequest();
            del.setMethod('DELETE');
            del.setEndpoint(
                'callout:' + S3_NC + '/' + key +
                '?uploadId=' + EncodingUtil.urlEncode(uploadId,'UTF-8')
            );
            del.setTimeout(TIMEOUT);
            new Http().send(del);
        } catch (Exception e) {
            System.debug('Abort failed: ' + e.getMessage());
        }
    }

    private static String extract(String xml, String tag) {
        Matcher m = Pattern.compile('<' + tag + '>([^<]+)</' + tag + '>')
                           .matcher(xml);
        return m.find() ? m.group(1) : '';
    }

    public class UploadException extends Exception {}
}