# AWS Lambda & API Gateway

This project ships with two Python 3.13 Lambdas used by the Salesforce
components. Each folder contains an AWS SAM template so the functions can be
built and deployed with `sam build && sam deploy --guided`.  For a single stack
deployment of **both** functions the repository root now provides
[`template.yml`](../template.yml) together with a checked‑in `samconfig.toml`
that supplies the stack name, region and an auto‑managed S3 bucket:

```bash
sam build && sam deploy --stack-name s3-doc-viewer --guided
```

## GenerateS3PresignedUrl

- **Folder:** `lambda/GenerateS3PresignedUrl`
- **Purpose:** returns short‑lived pre‑signed S3 URLs for uploads and downloads
- **API Gateway routes:**
  - `POST /generate-presigned-url` – body `{"fileName","contentType","fileSize"}` → `{ "uploadUrl", "s3Key" }`
  - `POST /generate-presigned-get-url` – body `{ "s3Key" }` → `{ "downloadUrl" }`
- **Environment variables:** `BUCKET` – target S3 bucket (default `avivdocdev`)
- **Notes:** allows only `.txt`, `.pdf`, `.png`, `.jpg`, `.jpeg`, `.docx`, `.msg`, `.eml`, `.gif` up to 200 MB; URLs expire after 5 minutes
- **Deploy:**
  ```bash
  cd lambda/GenerateS3PresignedUrl
  sam build && sam deploy --stack-name presign-lambda --guided
  ```

## MsgToEml

- **Folder:** `lambda/MsgToEml`
- **Purpose:** downloads an Outlook `.msg` from S3 and returns HTML plus base64
  encoded attachments
- **API Gateway route:** `GET /convert?key=<s3-key>` → `{ "html", "attachments" }`
- **Environment variables:** `TARGET_BUCKET` – bucket holding the source `.msg`
  files (default `avivdocdev`)
- **Notes:** skips attachments larger than 10 MB
- **Deploy:**
  ```bash
  cd lambda/MsgToEml
  sam build && sam deploy --stack-name msg-to-eml --guided
  ```

Both templates include minimal IAM permissions for S3 access and CloudWatch
logging; adjust them for production environments.
