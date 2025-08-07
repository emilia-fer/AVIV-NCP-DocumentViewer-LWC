/**
 * Verifies that the Named Credential can PUT & GET an object in S3.
 * Run once in Execute Anonymous before proceeding.
 */
public class FileSyncSmokeTest {

    public static void run() {
        String key = 'test/smoke-' + Datetime.now().getTime() + '.txt';
        String body = 'hello from Salesforce @ ' + Datetime.now();

        // ---- PUT ----------------------------------------------------------
        HttpRequest putReq = new HttpRequest();
        putReq.setEndpoint('callout:AWS_S3/' + key);
        putReq.setMethod('PUT');
        putReq.setHeader('Content-Type', 'text/plain');
        putReq.setBody(body);

        Http h = new Http();
        HttpResponse putResp = h.send(putReq);
        System.assertEquals(200, putResp.getStatusCode(),
            'PUT failed – check Named Credential');

        // ---- GET ----------------------------------------------------------
        HttpRequest getReq = new HttpRequest();
        getReq.setEndpoint('callout:AWS_S3/' + key);
        getReq.setMethod('GET');

        HttpResponse getResp = h.send(getReq);
        System.assertEquals(200, getResp.getStatusCode(),
            'GET failed – check bucket policy / region');
        System.assertEquals(body, getResp.getBody(),
            'Round-trip body mismatch');

        System.debug('✅  S3 callouts work – ready for the batch.');
    }
}