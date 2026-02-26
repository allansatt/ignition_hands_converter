import io
import json
import os
import re

import boto3
from src.convert import convert_ignition_to_open_hh

KEY_PATTERN = re.compile(r"^users/([^/]+)/uploads/([^/]+)/(.+)$")


def lambda_handler(event, context):
    s3 = boto3.client("s3")
    table = boto3.resource("dynamodb").Table(os.environ["POKERHANDS_JOBS_TABLE"])

    for record in event.get("Records", []):
        _process_record(record, s3, table)

    return {"statusCode": 200}


def _process_record(record, s3, table):
    eb_event = json.loads(record["body"])
    detail = eb_event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    object_key = detail.get("object", {}).get("key", "")

    # Ignore our own transcoded output (would re-trigger on put_object).
    if "/transcoded/" in object_key:
        return

    match = KEY_PATTERN.match(object_key)
    if not match:
        return  # skip other non-upload keys

    user_id, request_id, original_name = match.groups()
    base_name = re.sub(r"\.[^.]+$", "", original_name)
    transcoded_key = f"users/{user_id}/transcoded/{request_id}/{base_name}.json"

    try:
        job_key = _get_job_key(table, user_id, request_id)
        _transcode(s3, table, bucket, object_key, job_key, transcoded_key)
    except Exception as exc:
        try:
            job_key = _get_job_key(table, user_id, request_id)
            _update_job_status(table, job_key, "failed", error_message=str(exc))
        except Exception:
            pass
        raise


def _get_job_key(table, user_id, request_id):
    """Resolve (userId, jobId) to table primary key (userId, createdAt) via GSI."""
    result = table.query(
        IndexName="jobId-index",
        KeyConditionExpression="jobId = :jid",
        ExpressionAttributeValues={":jid": request_id},
    )
    for item in result.get("Items", []):
        if item.get("userId") == user_id:
            return {"userId": user_id, "createdAt": item["createdAt"]}
    raise ValueError(f"Job not found: {request_id}")


def _update_job_status(table, job_key, status, transcoded_key=None, error_message=None):
    update_expr = "SET #s = :s"
    values = {":s": status}
    if transcoded_key is not None:
        update_expr += ", transcodedKey = :tk"
        values[":tk"] = transcoded_key
    if error_message is not None:
        update_expr += ", errorMessage = :em"
        values[":em"] = error_message
    table.update_item(
        Key=job_key,
        UpdateExpression=update_expr,
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues=values,
    )


def _transcode(s3, table, bucket, object_key, job_key, transcoded_key):
    resp = s3.get_object(Bucket=bucket, Key=object_key)
    body_text = resp["Body"].read().decode("utf-8")

    hands = convert_ignition_to_open_hh(io.StringIO(body_text))

    output = json.dumps([h.model_dump() for h in hands], default=str)
    s3.put_object(Bucket=bucket, Key=transcoded_key, Body=output)

    _update_job_status(table, job_key, "completed", transcoded_key=transcoded_key)
