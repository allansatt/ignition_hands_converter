# Hand-history API Lambda handlers.

import json
import os
import re
import time
import uuid
import boto3


def upload_handler(event, context):
    """Return presigned PUT URL and job id. Use only userId from Cognito JWT (requestContext.authorizer.claims.sub)."""
    bucket = os.environ.get("POKERHANDS_BUCKET", "")
    table_name = os.environ.get("POKERHANDS_JOBS_TABLE", "")
    if not bucket or not table_name:
        return _resp(500, {"error": "Missing bucket or table config"})

    try:
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        user_id = claims.get("sub")
        if not user_id:
            return _resp(401, {"error": "Unauthorized"})
    except (TypeError, AttributeError):
        return _resp(401, {"error": "Unauthorized"})

    body = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        except json.JSONDecodeError:
            pass
    raw_filename = (body.get("filename") or "upload.txt").strip()
    filename = _sanitize_filename(raw_filename) or "upload.txt"
    job_id = uuid.uuid4().hex
    upload_key = f"users/{user_id}/uploads/{job_id}/{filename}"

    s3 = boto3.client("s3")
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)
    table.put_item(
        Item={
            "userId": user_id,
            "jobId": job_id,
            "uploadKey": upload_key,
            "status": "pending",
            "createdAt": int(time.time() * 1000),
        }
    )
    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": bucket, "Key": upload_key},
        ExpiresIn=900,
    )
    return _resp(200, {"uploadUrl": upload_url, "jobId": job_id})


def _sanitize_filename(name):
    """Remove path components and dangerous chars; return basename or None."""
    if not name:
        return None
    name = name.replace("\\", "/").strip()
    base = name.split("/")[-1].strip()
    base = re.sub(r"[^\w.\- ]", "_", base)
    return base[:255] if base else None


def _resp(status, body):
    return {"statusCode": status, "body": json.dumps(body), "headers": {"Content-Type": "application/json"}}


def list_handler(event, context):
    # TODO: query DynamoDB by userId from JWT, return list of files
    return {"statusCode": 501, "body": "Not implemented"}


def download_handler(event, context):
    # TODO: get jobId, get userId from JWT, lookup DynamoDB, return presigned GET URL
    return {"statusCode": 501, "body": "Not implemented"}
