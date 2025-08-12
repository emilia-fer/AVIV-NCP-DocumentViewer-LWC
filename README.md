# S3 Doc Viewer Suite for Salesforce  + AWS 

A Lightning Web Component bundle that lets users **store, preview and manage
documents living in Amazon S3** directly from Account / Opportunity /
Contact / Case / Task pages.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Repo Layout](#repo-layout)
4. [Prerequisites](#prerequisites)
5. [Salesforce Metadata](#salesforce-metadata)
6. [AWS Infrastructure](#aws-infrastructure)
7. [Static Resources](#static-resources)
8. [Deployment](#deployment)
9. [Post‑Install Configuration](#post-install-configuration)
10. [Usage](#usage)
11. [Testing](#testing)
12. [Extending the Package](#extending-the-package)
13. [Troubleshooting](#troubleshooting)

---

## Overview

|                   |                                                                                  |
| ----------------- | -------------------------------------------------------------------------------- |
| **Core LWC**      | `s3DocViewer` – lists files, filters, inline edit, previews & uploads            |
| **Helper LWCs**   | `pdfViewer`, `docxViewer` – lightweight wrappers around PDF.js / docx‑js         |
| **AWS Pieces**    | `generate-presigned-url` Lambda, `msg-to-html` Lambda, S3 bucket, API Gateway    |
| **Custom Object** | `S3_File__c` (look‑ups to Account, Opportunity, Contact, Case, **Task Id text**) |

---

## Architecture

```text
┌─────────────────────┐        putObject (pre‑signed URL)
│  s3DocViewer LWC    │───────────────────────────────► S3 Bucket
│  (user’s browser)   │◄──────── getObject  ───────────┘
│        ▲            │
│        │ Apex (NC)  │
│  Named Credential   │──► Lambda: generate‑presigned‑url (API GW) ─┐
└─────────────────────┘                                              │
                               Lambda: msg‑to‑html (for .msg files) ─┘
```

---

## Repo Layout

```text
.
├─ force-app
│  └─ main
│     └─ default
│        ├─ classes/              Apex controllers & tests
│        ├─ externalCredentials/
│        ├─ lwc/
│        │   ├─ s3DocViewer/      ← core component
│        │   ├─ pdfViewer/        ← helper
│        │   └─ docxViewer/       ← helper
│        ├─ namedCredentials/
│        ├─ objects/              Custom object **S3_File__c** & fields
│        ├─ permissionsets/
│        └─ staticresources/
├─ lambda/
│  ├─ GenerateS3PresignedUrl/  ← pre‑signed S3 URL service
│  └─ MsgToEml/                ← .msg → HTML converter
├─ docs/
│  ├─ metadata.md        Salesforce metadata & deployment notes
│  ├─ lambda.md          AWS Lambda & API Gateway setup
│  └─ developers.md      Component architecture
└─ README.md
```

---

## Prerequisites

- **Salesforce CLI (sfdx)** ≥ v7.0
- **AWS CLI** with a profile that can create S3 buckets & Lambda functions

---

## Salesforce Metadata

| Type              | API Name                                                                 | Notes                                                |
| ----------------- | ------------------------------------------------------------------------ | ---------------------------------------------------- |
| **Custom Object** | `S3_File__c`                                                             | Primary record for each file                         |
| Custom Fields     | see [`objects/S3_File__c/`](force-app/main/default/objects/S3_File__c)   | Includes `Task_ID__c` (Text)                         |
| Permission Set    | `AWS_S3_User`                                                            | Grants CRUD on **S3_File\_\_c**, Apex & NC access    |
| Permission Set    | `Msg_API_User`                                                           | Grants access to Msg Preview API credential          |
| Named Credential  | `AWS_S3`                                                                 | Direct S3 access via AWS SigV4                       |
| Named Credential  | `S3PresignAPI`                                                           | API Gateway for pre-signed URLs (OAuth 2 or API Key) |
| Named Credential  | `MsgPreviewAPI`                                                          | Lambda endpoint for `.msg` → HTML conversion         |
| Apex              | `S3DocService`, `S3PresignService`, `S3FileCreator`, `MsgPreviewService` | Business logic & callouts                            |

---

## AWS Infrastructure

| Resource        | Folder                          | Description                                                                                                             |
| --------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **S3 Bucket**   | —                               | Stores uploaded objects. CORS enabled (`PUT`, `GET`).                                                                   |
| **Lambda #1**   | `lambda/GenerateS3PresignedUrl` | Generates pre-signed S3 URLs for uploads and downloads.                                                                 |
| **Lambda #2**   | `lambda/MsgToEml`               | Converts `.msg` → HTML with inline attachments.                                                                         |
| **API Gateway** | —                               | Routes:<br>`/generate-presigned-url` → Lambda #1<br>`/generate-presigned-get-url` → Lambda #1<br>`/convert` → Lambda #2 |

> **Deployment**: both Lambdas can be zipped & deployed with AWS SAM:<br>
> `sam build && sam deploy --stack-name s3-doc-viewer --guided`

Environment variables used by the Lambdas:

| Name            | Example      | Meaning                                    |
| --------------- | ------------ | ------------------------------------------ |
| `BUCKET`        | `avivdocdev` | Target S3 bucket for uploads and downloads |
| `TARGET_BUCKET` | `avivdocdev` | Bucket containing `.msg` files to convert  |

---

## Static Resources

| Zip Name      | Used By      |
| ------------- | ------------ |
| `pdfjs.zip`   | `pdfViewer`  |
| `mammoth.zip` | `docxViewer` |

---

## Deployment

1. **Custom Object & Fields** – deploy `force-app/main/default/objects/S3_File__c` and all field metadata.
2. **External Credentials** – deploy `AWS_S3_Credential`, `AWS_Lambda_Cred` and `MsgPreviewAPICredential`.
3. **Named Credentials** – deploy `AWS_S3`, `S3PresignAPI` and `MsgPreviewAPI`; these point to the provided S3 bucket and Lambda URLs.
4. **Permission Sets** – deploy `AWS_S3_User` and `Msg_API_User` so users can access the external credentials.
5. **Static Resources** – deploy the zipped resources in `force-app/main/default/staticresources` (`pdfjs`, `mammoth`).
6. **Apex Classes & Tests** – deploy everything under `force-app/main/default/classes`.
7. **Lightning Web Components** – deploy all bundles in `force-app/main/default/lwc` (`s3DocViewer`, `pdfViewer`, `docxViewer`).

---

## Post‑Install Configuration

1. Add **S3 Doc Viewer** component to the Lightning page(s) you need.
2. Assign the `AWS_S3_User` and `Msg_API_User` permission sets to anyone using the component.

---

## Usage

- **Add File** → choose file, preview thumbnail, set look‑ups, _Upload_.
- Click a **file name** → inline preview (images, text, PDF, DOCX, EML, MSG).
- Click **More Columns** → adds Account / Opportunity / Contact / Case / Task
  columns _only when at least one row contains data_ for them.
- Use the **filter drawer** to slice by date, size, type, name or description.

---

## Testing

Run the Jest suite for Lightning Web Components:

```bash
npm install
npm test
```

Generate LWC and Apex coverage and refresh the markdown summary:

```bash
sf apex run test --target-org <org> --code-coverage --result-format json --output-dir coverage
npm run coverage:md
```

The CI workflow runs these commands on every push to keep `docs/code-coverage.md` up to date.

---

## Extending the Package

- **More MIME types**: update `mapMime()` in `s3DocViewer.js`.
- **Another look‑up**: create the field, add a column definition in
  `connectedCallback()`, extend `buildColumns()`.
- **Alternate storage**: swap the presign Lambda for SAS (Azure Blob),
  everything else stays client‑side.

---

## Troubleshooting

| Symptom                       | Possible Cause / Fix                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| “File type not allowed” toast | Add extension to `ALLOWED_EXTENSIONS` env var in presign Lambda                                   |
| “More Columns” button missing | Ensure `buildColumns()` is passed the **page slice** (`filteredAndSortedDocs`) not the whole list |
| MSG preview blank             | Check CloudWatch logs for `msg-to-html` Lambda; Outlook rule exceptions often break extraction    |


