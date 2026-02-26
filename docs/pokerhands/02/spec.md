# Feature: Poker Hands Upload, Transcode, and Download

**Revision**: 02  
**Status**: Draft  
**Created**: 2025-02-20

## Summary

Authenticated users can upload Ignition hand history files to the S3 bucket "pokerhands" via presigned URLs, have them transcoded to the open hand history format using the [ignition_hands_converter](https://github.com/allansatt/ignition_hands_converter) Python tool, and use a downloads page to list and download their transcoded files. Job and file metadata are stored in DynamoDB to drive the list API and link uploads to transcoded outputs. All new infrastructure for this feature is provisioned with Terraform.

**Service location**: This feature is implemented and deployed from **this repository** (ignition_hands_converter), not from a separate backend repo. The Cognito User Pool and any existing API Gateway may live elsewhere; this repo must be supplied with the **User Pool ID** (and any other required auth/API config) at deploy time—e.g. via Terraform variables or environment variables—so that the authorizer and user identity can be validated correctly.

## User stories

- **As a** signed-in user, **I want** to receive a presigned URL for the "pokerhands" bucket so that **I can** upload my hand history file directly to storage without sending the file through the API.
- **As a** signed-in user, **I want** my uploaded file to be transcoded automatically using the ignition_hands_converter tool so that **I can** use it in the open hand history format.
- **As a** signed-in user, **I want** a downloads page that lists my transcoded hand histories so that **I can** find and download them.
- **As a** signed-in user, **I want** to download a transcoded file via a secure, time-limited link so that **I can** retrieve it without exposing storage publicly.

## Acceptance criteria

- [ ] Authenticated requests to an "upload URL" endpoint return a presigned URL for the S3 bucket "pokerhands" with a key scoped to the requesting user.
- [ ] Client can upload a file to the returned presigned URL; the file is stored under a defined prefix for that user (e.g. uploads).
- [ ] After a file is uploaded, a transcoding process runs that uses the ignition_hands_converter Python logic to produce a transcoded output.
- [ ] Transcoded output is stored in S3 under a user-scoped prefix (e.g. transcoded) and is traceable to the original upload for listing.
- [ ] An authenticated "list my files" (or equivalent) capability returns the user's transcoded hand histories from DynamoDB (e.g. display name, job id, status, created date) so the downloads page can be populated.
- [ ] Authenticated requests can obtain a presigned download URL for a specific transcoded file the user owns; the URL is time-limited and does not expose long-lived credentials.
- [ ] Unauthenticated or invalid-token requests receive an appropriate error and do not receive presigned URLs or file listings.
- [ ] Only the owning user can list or download their own files; no cross-user access.
- [ ] Upload and transcode flows write job/file metadata to DynamoDB (e.g. job created on upload, transcoded key and status on completion) so the list API can return consistent, paginatable results.
- [ ] All new infrastructure for this feature (S3 bucket, DynamoDB table, Lambdas, IAM, event wiring, etc.) is defined and applied via Terraform.

## High-level design

- **API surface**: Expose endpoints under `/hand-history` protected by the existing Cognito authorizer: (1) request presigned upload URL (POST or GET), (2) list user's transcoded files (GET), (3) request presigned download URL for a given file (GET). These may be implemented via API Gateway plus Lambda or existing API stack; only net-new resources (e.g. Lambdas, S3, DynamoDB, IAM for this feature) are provisioned in Terraform.
- **Storage**: One S3 bucket named "pokerhands". Prefix-based layout per user: e.g. `users/{userId}/uploads/{requestId}/{originalName}` and `users/{userId}/transcoded/{requestId}/{outputName}`. This keeps ownership clear and aligns with DynamoDB item keys.
- **Metadata store (DynamoDB)**: A DynamoDB table stores job/file metadata per user. Key design: partition key `userId` (Cognito sub), sort key `jobId` (e.g. UUID or requestId). A GSI has partition key `jobId` only. Attributes can include: upload S3 key, transcoded S3 key (after completion), status (e.g. `pending`, `completed`, `failed`), original filename, created at, completed at. The "list my files" API queries the base table by `userId` (and sorts by `createdAt` in application if newest-first is needed); presigned download uses the transcoded key stored on the item. Terraform provisions the table and the GSI.
- **Upload flow**: Client calls API with auth; API validates Cognito JWT, generates a unique `requestId` and S3 key under `users/{userId}/uploads/...`, writes a DynamoDB item with status `pending` (and upload key), returns presigned PUT URL and optionally the job id. Client uploads file to the presigned URL. Upload completion triggers transcoding (e.g. S3 event notification to Lambda).
- **Transcoding**: A process (e.g. Lambda with Python runtime) is triggered when a new object appears in the uploads prefix. It retrieves the object from S3, runs the ignition_hands_converter logic (as library or subprocess), writes the transcoded output to the user's transcoded prefix, then updates the corresponding DynamoDB item with transcoded key and status `completed` (or `failed` with optional error info).
- **Downloads experience**: Frontend calls "list my files", which queries DynamoDB by `userId` (base table) and sorts by `createdAt` in application for newest-first. For each listed file the client requests a presigned GET URL from the API (using the job id; API looks up transcoded key in DynamoDB and generates presigned URL). The downloads page is the UI that shows the list and exposes download actions.
- **Auth**: Reuse existing Cognito User Pool; the **User Pool ID** (and any issuer/region needed for JWT validation) is supplied to this repo at deploy time. The authorizer is configured with that ID and validates JWT, passing `userId` (sub) so all keys, DynamoDB queries, and listings are scoped by identity.
- **Infrastructure**: Terraform modules (or root modules) define the "pokerhands" S3 bucket, the DynamoDB table (and GSIs), bucket policies, any Lambda functions and their IAM roles (including DynamoDB read/write), S3 event notifications, and integration points (e.g. API Gateway routes/Lambda permissions) for this feature. Existing CDK stacks are not extended for this feature; net-new resources are Terraform-managed.

## Constraints and assumptions

- **Cognito config supplied at deploy time**: The Cognito **User Pool ID** (and, if applicable, User Pool region or issuer URL) must be passed into this repo’s deployment—e.g. Terraform variables (`var.cognito_user_pool_id`), environment variables, or a config layer—so that API routes can use the correct authorizer and JWT validation. This repo does not create or own the User Pool; it consumes an existing one.
- Assumes existing Cognito-based auth; no new identity provider or SSO in scope.
- Assumes ignition_hands_converter is available as a callable Python component (library or CLI) and can be run in the same account/region (e.g. Lambda layer, container, or bundled in Lambda).
- S3 bucket "pokerhands" is created in Terraform with encryption and block public access; lifecycle/retention can be defined in Terraform or later.
- A DynamoDB table holds job/file metadata (userId, jobId, upload key, transcoded key, status, timestamps), with a GSI on `jobId`. The list API is driven by querying the base table by `userId` (and sorting by `createdAt` in application for newest-first); this supports pagination and consistent metadata without S3 list limits.

## Out of scope

- Support for unauthenticated upload or download.
- Transcoding to formats other than the open hand history format.
- Real-time progress UI for transcoding (polling or webhooks may be in scope; real-time push is out of scope unless added later).
- Deleting or overwriting existing uploads/transcoded files (no delete/update API in this feature).
- Public or shareable links to transcoded files; downloads are strictly for the owning user via presigned URLs.
- Changes to the ignition_hands_converter tool itself; it is consumed as-is.
- Provisioning this feature’s new resources via CDK; Terraform only for this feature.
