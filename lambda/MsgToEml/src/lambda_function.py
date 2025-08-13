import json, base64, boto3, tempfile, mimetypes, os, re
import extract_msg

s3      = boto3.client("s3")
BUCKET  = os.environ.get("TARGET_BUCKET", "avivdocdev")   # hard-coded

# helper
def to_str(x):  # decode bytes→str safely
    if isinstance(x, bytes):
        return x.decode("utf-8", errors="ignore")
    return x or ""

MAX_INLINE = 1_000_000      # skip embedding > 1 MB
MAX_TOTAL   = 10_000_000    # skip any single attachment > 10 MB

def lambda_handler(event, context):
    path = None
    msg = None
    try:
        params = event.get("queryStringParameters") or {}
        key    = params.get("key") or ""

        # ------- validate key -------
        if not re.fullmatch(r"[A-Za-z0-9@._\-\/]+", key):
            raise ValueError("Invalid key format")

        # ------- download from S3 -------
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            s3.download_fileobj(BUCKET, key, tmp)
            path = tmp.name

        msg  = extract_msg.Message(path)
        html = to_str(msg.htmlBody) if msg.htmlBody else to_str(msg.body)

        # ------- attachments -------
        atts = []
        for att in msg.attachments:
            if len(att.data) > MAX_TOTAL:
                continue  # too large – skip
            fname = att.longFilename or att.shortFilename or "attachment"
            ctype = getattr(att, "mimetype", None) or \
                    mimetypes.guess_type(fname)[0] or "application/octet-stream"
            atts.append({
                "filename": fname,
                "contentType": ctype,
                "contentId": getattr(att, "contentId", None),
                "data": base64.b64encode(att.data).decode("utf-8")
            })

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Security-Policy": "default-src 'none'; img-src data:; style-src 'unsafe-inline'"
            },
            "body": json.dumps({"html": html, "attachments": atts})
        }

    except Exception as e:
        print("ERROR:", e)
        return {
            "statusCode": 500,
            "headers": {"Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": str(e)})
        }
    finally:
        if msg:
            try:
                msg.close()
            except Exception:
                pass
        if path:
            try:
                os.remove(path)
            except OSError:
                pass