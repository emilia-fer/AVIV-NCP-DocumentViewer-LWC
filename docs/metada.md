# Metadata catalogue

This document is an **authoritative index** of all Salesforce metadata that
ships with **AVIV‑NCP‑DocumentViewer‑LWC**.  
Everything listed here is physically present in `force‑app/main/default`.

---

## 1. Custom object – `S3_File__c`

| Field Label (UI) | API Name | Type | Notes |
| ---------------- | -------- | ---- | ----- |
| Account ID | `Account_ID__c` | Lookup (Account) | Indexed |
| Case ID | `Case_ID__c` | Lookup (Case) | Indexed |
| Contact ID | `Contact_ID__c` | Lookup (Contact) | Indexed |
| Creation Date | `Creation_Date__c` | Date | — |
| Creation Year | `Creation_Year__c` | Number(4,0) | — |
| Description | `Description__c` | Text Area(255) | — |
| Opportunity ID | `Opportunity_ID__c` | Lookup (Opportunity) | Indexed |
| Record ID | `Record_ID__c` | Text(18) | For external correlation |
| S3 File Name | `Name` | Text(80) | Primary label |
| S3 Key | `S3_Key__c` | Text(255) | Full key in S3 |
| Size (bytes) | `Size__c` | Number(18,0) | Raw object size |
| Task ID | `Task_ID__c` | Text(18) | Plain‑text link to Task |
| Type | `Type__c` | Text(100) | MIME type |

*(The standard `OwnerId`, `CreatedById`, `LastModifiedById` system fields are present but omitted for brevity).*

---

## 2. Apex classes

| Name | Purpose |
| ---- | ------- |
| `S3DocService` / **Test** | SOQL façade used by the LWC to list & fetch records |
| `S3FileCreator` | Creates `S3_File__c` after a successful S3 upload |
| `MsgPreviewService` / **Test** | Calls Lambda to convert *.msg* → HTML |
| `ObjectList`, `ObjectAdd` (+ **Tests**) | Generic helpers used in unit tests |

*(All `*.cls` and `*.cls-meta.xml` files live under `classes/`).*

---

## 3. Lightning Web Components

| Folder | Description |
| ------ | ----------- |
| `lwc/s3DocViewer` | Main document viewer / uploader |
| `lwc/pdfViewer`  | Tiny wrapper around **PDF.js** static‑resource |
| `lwc/docxViewer` | Uses **Mammoth** static‑resource to render *.docx* |

---

## 4. Static Resources

| Name | Contents |
| ---- | -------- |
| `pdfjs` | **PDF.js 3.6+** build (application/zip) – used by `pdfViewer` |
| `mammoth` | **Mammoth.js** (docx → HTML) build (application/zip) |

*(See `staticresources/` for the actual `.resource` + `.resource‑meta.xml` files).*

---

## 5. External Credentials & Named Credentials

| Logical name | Type | XML file | Notes |
|--------------|------|----------|-------|
| **AWS S3 Credential** | `ExternalCredential` | `AWS_S3_Credential.externalCredential-meta.xml` | Signed with **AWS SigV4** for S3 access  |
| **AWS S3** | `NamedCredential` | `AWS_S3.namedCredential-meta.xml` | Points to `https://avivdocdev.s3.eu-north-1.amazonaws.com` and references the external cred above |
| **Msg Preview API Credential** | `ExternalCredential` | `MsgPreviewAPICredential.externalCredential-meta.xml` | SigV4 for the Lambda API |
| **Msg Preview API** | `NamedCredential` | `MsgPreviewAPI.namedCredential-meta.xml` | URL: `https://ixsx2em9v6.execute-api.eu-north-1.amazonaws.com`|
| **AWS Lambda Cred** | `ExternalCredential` | `AWS_Lambda_Cred.externalCredential-meta.xml` | Used by the unit tests / future Lambdas |

---

## 6. Permission Sets

| Label | Grants access to |
| ----- | ---------------- |
| `AWS S3 User` | Principal access to **AWS S3 Credential** and **AWS Lambda Cred** |
| `Msg_API_User` | Principal access to **Msg Preview API Credential** |


