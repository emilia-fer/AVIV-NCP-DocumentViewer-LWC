import os
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BUCKET = os.environ.get("BUCKET")
ALLOWED_EXTENSIONS = {".txt", ".pdf", ".png", ".jpg", ".jpeg", ".docx", ".msg", ".eml", ".gif"}
MAX_SIZE = 200 * 1024 * 1024  # 200 MB

def _resp(status, body):
    return {
        'statusCode': status,
        'headers': {
            'Access-Control-Allow-Origin': '*',  # CORS: Adjust for prod
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body)
    }

def get_body(event):
    # Handles various invocation types (API Gateway, test, etc.)
    body = event.get('body', event)
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except Exception:
            pass
    return body

def generate_presigned_url(event):
    try:
        body = get_body(event)
        file_name = body.get('fileName')
        content_type = body.get('contentType')
        file_size = body.get('fileSize', 0)
        if not file_name or not content_type:
            return _resp(400, {'error': 'fileName and contentType required'})

        ext = os.path.splitext(file_name)[-1].lower()
        if ext not in ALLOWED_EXTENSIONS:
            return _resp(400, {'error': f'File type not allowed: {ext}'})

        if file_size and int(file_size) > MAX_SIZE:
            return _resp(400, {'error': f'File too large (>{MAX_SIZE} bytes)'})

        s3_key = f"uploads/{file_name}"

        s3 = boto3.client('s3')
        url = s3.generate_presigned_url(
            ClientMethod='put_object',
            Params={
                'Bucket': BUCKET,
                'Key': s3_key,
                'ContentType': content_type
            },
            ExpiresIn=300  # 5 minutes
        )
        logger.info(f"Generated presigned upload URL for {file_name}")
        return _resp(200, {
            'uploadUrl': url,
            's3Key': s3_key
        })

    except Exception as e:
        logger.error(f"Upload error: {str(e)}", exc_info=True)
        return _resp(500, {'error': str(e)})

def generate_presigned_get_url(event):
    try:
        body = get_body(event)
        s3_key = body.get('s3Key')
        if not s3_key:
            return _resp(400, {'error': 's3Key required'})

        s3 = boto3.client('s3')
        url = s3.generate_presigned_url(
            ClientMethod='get_object',
            Params={'Bucket': BUCKET, 'Key': s3_key},
            ExpiresIn=300  # 5 minutes
        )
        logger.info(f"Generated presigned GET URL for {s3_key}")
        return _resp(200, {'downloadUrl': url})
    except Exception as e:
        logger.error(f"Download error: {str(e)}", exc_info=True)
        return _resp(500, {'error': str(e)})

def lambda_handler(event, context):
    """Dispatch based on HTTP path."""
    logger.info(json.dumps(event))

    path = event.get('rawPath') or event.get('path', '')
    method = (event.get('requestContext', {}).get('http', {}).get('method', '') or event.get('httpMethod', '')).upper()

    # Normalise path, drop trailing slashes for matching
    path = path.rstrip('/')

    if method == 'POST' and path.endswith('/generate-presigned-url'):
        return generate_presigned_url(event)
    if method == 'POST' and path.endswith('/generate-presigned-get-url'):
        return generate_presigned_get_url(event)

    # $default route (fallback)
    return _resp(404, {'error': 'Not found'})
