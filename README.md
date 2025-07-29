
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
8. [Installation & Deployment](#installation--deployment)
9. [Post‑Install Configuration](#post-install-configuration)
10. [Usage](#usage)
11. [Extending the Package](#extending-the-package)
12. [Troubleshooting](#troubleshooting)
13. [License](#license)

---

## Overview
| | |
|---|---|
| **Core LWC** | `s3DocViewer` – lists files, filters, inline edit, previews & uploads |
| **Helper LWCs** | `pdfViewer`, `docxViewer` – lightweight wrappers around PDF.js / docx‑js |
| **AWS Pieces** | `generate-presigned-url` Lambda, `msg-to-html` Lambda, S3 bucket, API Gateway |
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
````

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
│  ├─ presign/          generate‑presigned‑url 
│  └─ msg-to-html/      .msg → eml converter  
└─ README.md
```

---

## Prerequisites

* **Salesforce CLI (sfdx)** ≥ v7.0
* **AWS CLI** with a profile that can create S3 buckets & Lambda functions
* Node 18 LTS (for LWC dev & serverless deployments)

---

## Salesforce Metadata

| Type              | API Name                                                                 | Notes                                                   |
| ----------------- | ------------------------------------------------------------------------ | ------------------------------------------------------- |
| **Custom Object** | `S3_File__c`                                                             | Primary record for each file                            |
| Custom Fields     | see [`objects/S3_File__c/`](force-app/main/default/objects/S3_File__c)                                 | Includes `Task_ID__c` (Text)                            |
| Permission Set    | `S3_Doc_Viewer_User`                                                     | Grants CRUD on **S3\_File\_\_c**, Apex & NC access      |
| Named Credential  | `S3PresignAPI`                                                           | Points to API Gateway endpoint, uses OAuth 2 or API Key |
| Apex              | `S3DocService`, `S3PresignService`, `S3FileCreator`, `MsgPreviewService` | Business logic & callouts                               |

---

## AWS Infrastructure

| Resource        | Folder               | Description                                                                                 |
| --------------- | -------------------- | ------------------------------------------------------------------------------------------- |
| **S3 Bucket**   | —                    | Stores uploaded objects. CORS enabled (`PUT`, `GET`).                                       |
| **Lambda #1**   | `lambda/presign`     | Returns a 5‑min pre‑signed `putObject` URL.                                                 |
| **Lambda #2**   | `lambda/msg-to-html` | Converts `.msg` → HTML + inline attachments.                                                |
| **API Gateway** | —                    | *Resource:* `/generate-presigned-url` → Lambda #1<br>*Resource:* `/msg-preview` → Lambda #2 |

> **Deployment**: both Lambdas can be zipped & deployed with AWS SAM:<br>
> `sam build && sam deploy --stack-name s3-doc-viewer --guided`

Environment variables used by the Lambdas:

| Name                 | Example                                     | Meaning                |
| -------------------- | ------------------------------------------- | ---------------------- |
| `BUCKET`             | `avivdocdev`                                | Target S3 bucket       |
| `ALLOWED_EXTENSIONS` | `.txt,.pdf,.png,.jpg,.jpeg,.docx,.msg,.eml` | Server‑side validation |
| *etc.*               |                                             |                        |

---

## Static Resources

| Zip Name          | Used By      |
| ----------------  | ------------ |
| `pdfjs.zip`      | `pdfViewer`  |
| `mammoth.zip`     | `docxViewer` |

---

## Post‑Install Configuration

1. Add **S3 Doc Viewer** component to the Lightning page(s) you need.
2. Ensure the running user has the `S3_Doc_Viewer_User` permission set.
3. (Optional) Restrict file‑type whitelist in `lambda/presign/app.py`.

---

## Usage

* **Add File** → choose file, preview thumbnail, set look‑ups, *Upload*.
* Click a **file name** → inline preview (images, text, PDF, DOCX, EML, MSG).
* Click **More Columns** → adds Account / Opportunity / Contact / Case / Task
  columns *only when at least one row contains data* for them.
* Use the **filter drawer** to slice by date, size, type, name or description.

---

## Extending the Package

* **More MIME types**: update `mapMime()` in `s3DocViewer.js`.
* **Another look‑up**: create the field, add a column definition in
  `connectedCallback()`, extend `buildColumns()`.
* **Alternate storage**: swap the presign Lambda for SAS (Azure Blob),
  everything else stays client‑side.

---

## Troubleshooting

| Symptom                       | Possible Cause / Fix                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------------- |
| “File type not allowed” toast | Add extension to `ALLOWED_EXTENSIONS` env var in presign Lambda                                   |
| “More Columns” button missing | Ensure `buildColumns()` is passed the **page slice** (`filteredAndSortedDocs`) not the whole list |
| MSG preview blank             | Check CloudWatch logs for `msg-to-html` Lambda; Outlook rule exceptions often break extraction    |


