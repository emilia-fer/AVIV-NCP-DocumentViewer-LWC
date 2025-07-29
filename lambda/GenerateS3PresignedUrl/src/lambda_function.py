import os
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
import boto3, logging, os, json
logging.info(boto3.client("sts").get_caller_identity())


# Set these via environment variables
BUCKET = os.environ.get("BUCKET")
ALLOWED_EXTENSIONS = {".txt", ".pdf", ".png", ".jpg", ".jpeg", ".docx", ".msg", ".eml"}  
MAX_SIZE = 10 * 1024 * 1024  # 10MB

def lambda_handler(event, context):
    try:
        # For HTTP API Gateway, body is already parsed
        if 'body' in event:
            body = event['body']
            if isinstance(body, str):
                body = json.loads(body)
        else:
            body = event
        
        file_name = body.get('fileName')
        content_type = body.get('contentType')
        file_size = body.get('fileSize', 0)  
        if not file_name or not content_type:
            return _resp(400, {'error': 'fileName and contentType required'})

        # Check allowed file extensions
        ext = os.path.splitext(file_name)[-1].lower()
        if ext not in ALLOWED_EXTENSIONS:
            return _resp(400, {'error': f'File type not allowed: {ext}'})

        # Optional: file size restriction
        if file_size and int(file_size) > MAX_SIZE:
            return _resp(400, {'error': f'File too large (>{MAX_SIZE} bytes)'})

        # Key: can use a folder or prefix pattern 
        s3_key = f"uploads/{file_name}"  # or just file_name

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

        logger.info(f"Generated presigned URL for {file_name}")

        return _resp(200, {
            'uploadUrl': url,
            's3Key': s3_key  # Let the client know where to look later
        })

    except Exception as e:
        logger.error(f"Error: {str(e)}", exc_info=True)
        return _resp(500, {'error': str(e)})

def _resp(status, body):
    return {
        'statusCode': status,
        'headers': {
            'Access-Control-Allow-Origin': '*',  # for CORS, restrict in prod
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body)
    }
