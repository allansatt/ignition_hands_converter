import json
import os
import re
import time
import uuid

import boto3


def _get_user_id(event):
    ctx = event.get("requestContext") or {}
    auth = ctx.get("authorizer") or {}
    claims = auth.get("claims") or {}
    return claims.get("sub")


def _sanitize_filename(name):
    if not name:
        return None
    name = name.replace("\\", "/").strip()
    base = name.split("/")[-1].strip()
    base = re.sub(r"[^\w.\- ]", "_", base)
    return base[:255] if base else None


def _resp(status, body):
    return {"statusCode": status, "body": json.dumps(body, default=str), "headers": {"Content-Type": "application/json"}}


def _parse_body(event):
    raw = event.get("body")
    if not raw:
        return {}
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def upload_handler(event, context):
    bucket = os.environ.get("POKERHANDS_BUCKET", "")
    table_name = os.environ.get("POKERHANDS_JOBS_TABLE", "")
    if not bucket or not table_name:
        return _resp(500, {"error": "Missing bucket or table config"})

    user_id = _get_user_id(event)
    if not user_id:
        return _resp(401, {"error": "Unauthorized"})

    body = _parse_body(event)
    raw_filename = (body.get("filename") or "upload.txt").strip()
    filename = _sanitize_filename(raw_filename) or "upload.txt"
    job_id = uuid.uuid4().hex
    upload_key = f"users/{user_id}/uploads/{job_id}/{filename}"

    s3 = boto3.client("s3")
    table = boto3.resource("dynamodb").Table(table_name)
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


def list_handler(event, context):
    table_name = os.environ.get("POKERHANDS_JOBS_TABLE", "")
    if not table_name:
        return _resp(500, {"error": "Missing table config"})

    user_id = _get_user_id(event)
    if not user_id:
        return _resp(401, {"error": "Unauthorized"})

    params = event.get("queryStringParameters") or {}
    limit = min(int(params.get("limit", 50)), 100)

    table = boto3.resource("dynamodb").Table(table_name)

    query_kwargs = {
        "KeyConditionExpression": "userId = :uid",
        "ExpressionAttributeValues": {":uid": user_id},
        "Limit": limit,
    }
    if params.get("nextToken"):
        try:
            query_kwargs["ExclusiveStartKey"] = json.loads(params["nextToken"])
        except json.JSONDecodeError:
            pass

    result = table.query(**query_kwargs)
    items = sorted(result.get("Items", []), key=lambda x: x.get("createdAt", 0), reverse=True)

    response_items = []
    for item in items:
        upload_key = item.get("uploadKey", "")
        display_name = upload_key.rsplit("/", 1)[-1] if upload_key else item.get("jobId", "")
        response_items.append({
            "displayName": display_name,
            "jobId": item.get("jobId"),
            "status": item.get("status"),
            "createdAt": item.get("createdAt"),
        })

    body = {"items": response_items}
    last_key = result.get("LastEvaluatedKey")
    if last_key:
        body["nextToken"] = json.dumps(last_key)

    return _resp(200, body)


def download_handler(event, context):
    bucket = os.environ.get("POKERHANDS_BUCKET", "")
    table_name = os.environ.get("POKERHANDS_JOBS_TABLE", "")
    if not bucket or not table_name:
        return _resp(500, {"error": "Missing bucket or table config"})

    user_id = _get_user_id(event)
    if not user_id:
        return _resp(401, {"error": "Unauthorized"})

    params = event.get("queryStringParameters") or {}
    job_id = params.get("jobId")
    if not job_id:
        return _resp(400, {"error": "Missing jobId query parameter"})

    table = boto3.resource("dynamodb").Table(table_name)
    result = table.get_item(Key={"userId": user_id, "jobId": job_id})
    item = result.get("Item")
    if not item:
        return _resp(404, {"error": "Job not found"})

    if item.get("status") != "completed":
        return _resp(409, {"error": f"Job is {item.get('status', 'unknown')}, not yet completed"})

    transcoded_key = item.get("transcodedKey")
    if not transcoded_key:
        return _resp(404, {"error": "Transcoded file not found"})

    s3 = boto3.client("s3")
    download_url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": transcoded_key},
        ExpiresIn=900,
    )
    return _resp(200, {"downloadUrl": download_url})
