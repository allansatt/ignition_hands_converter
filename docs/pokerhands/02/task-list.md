# Task list: Poker Hands Upload, Transcode, and Download

**Spec**: docs/pokerhands/02/spec.md  
**Generated**: 2025-02-20  
**Enriched**: 2025-02-20

**API base**: All hand-history API endpoints will be served at **`https://api.allansattelbergrivera.com`** (custom domain; you own the domain and will point DNS to API Gateway).

## Recommended technologies

- **AWS**: S3 (bucket "pokerhands", presigned URLs), Lambda (upload URL API, list API, download URL API, transcode worker), DynamoDB (job/file metadata), API Gateway (Cognito-protected routes, custom domain), IAM (Lambda roles, bucket policies), Cognito (existing User Pool; ID supplied at deploy), **EventBridge** (receive S3 object-created events), **SQS** (transcode job queue + DLQ for retries and failed messages). **ACM**: An existing certificate for `api.allansattelbergrivera.com` is referenced in Terraform via a **data source** (e.g. `aws_acm_certificate`), not created by this repo.
- **Python**: Lambda runtimes and the existing converter in this repo (`src.convert.convert_ignition_to_open_hh`) used as a library for transcoding (no CLI; invoke with a file-like text stream).
- **Terraform**: All net-new infrastructure—S3 bucket, DynamoDB table, Lambdas, IAM, EventBridge rule, SQS queue and DLQ, Lambda event source mapping (SQS → transcode Lambda), API Gateway integration and custom domain; Cognito User Pool ID and API domain supplied via variables.

## Tasks

### Infrastructure (Terraform)

- [x] Use Terraform to provision the S3 bucket "pokerhands" with encryption and block public access; define prefix layout `users/{userId}/uploads/{requestId}/{originalName}` and `users/{userId}/transcoded/{requestId}/{outputName}`.
- [x] Use Terraform to provision the DynamoDB table for job/file metadata with partition key `userId`, sort key `jobId`; add a GSI with partition key `jobId` only.
- [x] Define Terraform variables for Cognito User Pool ID (and issuer/region if needed) and for the API domain (`api.allansattelbergrivera.com`) so the authorizer and custom domain use the correct values at deploy time.
- [x] Use Terraform to create IAM roles and policies for Lambda: S3 read/write for the pokerhands bucket, DynamoDB read/write for the jobs table, SQS receive message and delete message for the transcode queue (for the transcode Lambda), and least-privilege for each API Lambda. Grant EventBridge permission to send messages to the transcode SQS queue.
- [x] Use Terraform to create an SQS queue for transcode jobs and a DLQ (dead-letter queue); set the main queue’s redrive policy so messages that fail after a configured max receive count are sent to the DLQ for retry handling and inspection.
- [x] Use Terraform to configure EventBridge to receive S3 object-created events for the pokerhands bucket (uploads prefix), add an EventBridge rule that targets the transcode SQS queue, and ensure the transcode Lambda is triggered by the SQS queue (Lambda event source mapping) instead of S3 directly—so failed Lambda invocations are retried via SQS and eventually moved to the DLQ.
- [x] Use Terraform to define the transcode Lambda (Python), package or layer the code from this repo (e.g. `src/convert.py` and `open_hh_models` dependency), and attach the Lambda’s event source to the transcode SQS queue (EventBridge → SQS → Lambda).
- [x] Use Terraform to define API Gateway REST API with routes under `/hand-history`: (1) request presigned upload URL, (2) list user's transcoded files, (3) request presigned download URL; wire each route to its Lambda and attach the Cognito authorizer using the supplied User Pool ID.
  - [x] Configure the Cognito authorizer so unauthenticated or invalid-token requests receive 401 (no presigned URLs or file listings).
- [x] Configure API Gateway custom domain so the API is served at `https://api.allansattelbergrivera.com`: reference the **existing** ACM certificate for `api.allansattelbergrivera.com` using a Terraform **data source** (e.g. `aws_acm_certificate` by domain or ARN), then create the API Gateway domain name and base path mapping using that certificate; document that `api.allansattelbergrivera.com` (DNS CNAME or A/ALIAS) points to the API Gateway endpoint.

### API and upload flow

- [x] Implement the presigned upload URL Lambda: validate Cognito JWT and extract `userId` (sub), generate a unique `requestId` (e.g. UUID), build S3 key `users/{userId}/uploads/{requestId}/{originalFilename}` (sanitize filename), write DynamoDB item with `userId`, `jobId` (= requestId), upload key, status `pending`, and `createdAt`, return presigned PUT URL and job id.
  - [x] Use only the authenticated user's `userId` from the JWT for S3 key and DynamoDB; do not accept userId from the request body.
- [x] Enforce that only the owning user can list or download their own files: in list and download handlers, use only `userId` from the Cognito JWT for DynamoDB queries and presigned URL generation; do not allow access by job id alone without verifying item ownership.

### Transcoding

- [x] Implement the transcode Lambda: on SQS message (payload is EventBridge event for S3 object-created), read the object key from the event detail, parse `userId` and `requestId` from the key (e.g. `users/{userId}/uploads/{requestId}/...`), load the object body from S3, run `convert_ignition_to_open_hh(io.StringIO(body))` from `src.convert` (or equivalent file-like input), serialize the returned hands to the open hand history format (e.g. JSON via Pydantic `model_dump_json()`), write the output to `users/{userId}/transcoded/{requestId}/{outputName}` in S3, then update the DynamoDB item for `userId` + `jobId` with transcoded key and status `completed` (or `failed` and optional error message on exception). On success, delete the message from the queue; on failure, let it retry (and eventually move to the DLQ after max receives).
  - [x] Package this repo's `src` and dependencies (e.g. `ohh-pydantic`, `pydantic`) into the Lambda deployment package or a layer so the Lambda can import `src.convert`.

### List and download

- [x] Implement the "list my files" Lambda: query the base table by `userId` (from JWT), sort by `createdAt` in application so results are **newest first**; return display name (original filename), job id, status, created date for each item; support pagination (e.g. `limit` and `lastEvaluatedKey` / `nextToken`).
- [x] Implement the presigned download URL Lambda: accept job id (path or query), get `userId` from JWT, get DynamoDB item by `userId` and `jobId`, verify the item exists and belongs to the user, read `transcodedKey` from the item, generate a time-limited presigned GET URL for that S3 key, and return it.
