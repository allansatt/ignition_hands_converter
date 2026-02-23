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

    match = KEY_PATTERN.match(object_key)
    if not match:
        raise ValueError(f"Unexpected S3 key format: {object_key}")

    user_id, request_id, original_name = match.groups()
    base_name = re.sub(r"\.[^.]+$", "", original_name)
    transcoded_key = f"users/{user_id}/transcoded/{request_id}/{base_name}.json"

    try:
        _transcode(s3, table, bucket, object_key, user_id, request_id, transcoded_key)
    except Exception as exc:
        table.update_item(
            Key={"userId": user_id, "jobId": request_id},
            UpdateExpression="SET #s = :s, errorMessage = :em",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "failed", ":em": str(exc)},
        )
        raise


def _transcode(s3, table, bucket, object_key, user_id, request_id, transcoded_key):
    resp = s3.get_object(Bucket=bucket, Key=object_key)
    body_text = resp["Body"].read().decode("utf-8")

    hands = convert_ignition_to_open_hh(io.StringIO(body_text))

    output = json.dumps([h.model_dump() for h in hands], default=str)
    s3.put_object(Bucket=bucket, Key=transcoded_key, Body=output)

    table.update_item(
        Key={"userId": user_id, "jobId": request_id},
        UpdateExpression="SET #s = :s, transcodedKey = :tk",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "completed", ":tk": transcoded_key},
    )
