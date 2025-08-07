# Developer guide

This document explains the internal architecture of the S3 Doc Viewer suite
and where to add new features.

## Lightning Web Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `s3DocViewer` | `force-app/main/default/lwc/s3DocViewer` | Main UI for listing, uploading and previewing `S3_File__c` records. Calls multiple Apex services for data and S3 access. |
| `pdfViewer` | `force-app/main/default/lwc/pdfViewer` | Wraps the `pdfjs` static resource to display PDFs. |
| `docxViewer` | `force-app/main/default/lwc/docxViewer` | Uses the `mammoth` static resource to render `.docx` files. |
| `msgViewer` | `force-app/main/default/lwc/msgViewer` | Renders Outlook `.msg` files by embedding HTML returned from `MsgPreviewService.fetch`. |
| `test_component` | `force-app/main/default/lwc/test_component` | Simple harness used by the Jest tests. |

### s3DocViewer flow
1. Fetches records via `S3DocService.getDocs`.
2. Uploads files by requesting a pre‑signed URL from `S3PresignService.getPresignedUrl` and then calling `S3FileCreator.create` to insert the record.
3. Downloads files using `S3PresignService.getPresignedGetUrl`.
4. Previews `.msg` files by calling `MsgPreviewService.fetch` and passing the returned HTML to `msgViewer`.

## Apex classes

| Class | Location | Role |
|-------|----------|------|
| `S3DocService` | `force-app/main/default/classes/S3DocService.cls` | SOQL façade for `S3_File__c` and helper queries for related records. |
| `S3FileCreator` | `force-app/main/default/classes/S3FileCreator.cls` | Inserts `S3_File__c` rows after a successful upload. |
| `S3PresignService` | `force-app/main/default/classes/S3PresignService.cls` | Calls the `S3PresignAPI` named credential to obtain pre‑signed upload and download URLs. |
| `MsgPreviewService` | `force-app/main/default/classes/MsgPreviewService.cls` | Invokes the `MsgPreviewAPI` named credential to convert `.msg` files to HTML. |
| `FileMultipartUploadJob`, `FileSyncBatch`, `FileSyncWorker`, `Sched_FileSync_Nightly` | `force-app/main/default/classes` | Background jobs for syncing `ContentVersion` records to S3 and performing chunked uploads. |
| `ObjectAdd`, `ObjectList` | `force-app/main/default/classes` | Lightweight helpers used in unit tests. |

All classes include corresponding `*Test` files to provide Apex unit coverage.

## Testing

Install Node dependencies once and execute the Jest suite for Lightning Web Components:

```bash
npm install
npm test
```

Apex tests can be run with the Salesforce CLI:

```bash
sfdx force:apex:test:run --resultformat human --codecoverage
```

## Related documentation

* [lambda.md](lambda.md) – AWS Lambda implementations
* [metadata.md](metadata.md) – catalogue of Salesforce metadata

