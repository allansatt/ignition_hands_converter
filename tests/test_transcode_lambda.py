import json
import os
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "terraform" / "service" / "lambda" / "transcode"))
import handler

BUCKET = "pokerhands"
TABLE = "pokerhands-jobs"
FIXTURE = Path(__file__).resolve().parent / "HH20250716-232414 - 21171592 - RING - $0.02-$0.05 - HOLDEM - NL - TBL No.35104085.txt"


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("POKERHANDS_BUCKET", BUCKET)
    monkeypatch.setenv("POKERHANDS_JOBS_TABLE", TABLE)

    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=BUCKET)

        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName=TABLE,
            KeySchema=[
                {"AttributeName": "userId", "KeyType": "HASH"},
                {"AttributeName": "jobId", "KeyType": "RANGE"},
            ],
            AttributeDefinitions=[
                {"AttributeName": "userId", "AttributeType": "S"},
                {"AttributeName": "jobId", "AttributeType": "S"},
            ],
            BillingMode="PAY_PER_REQUEST",
        )

        yield s3, dynamodb


def _sqs_event(bucket, key):
    eb_event = {
        "version": "0",
        "detail-type": "Object Created",
        "source": "aws.s3",
        "detail": {
            "bucket": {"name": bucket},
            "object": {"key": key},
        },
    }
    return {"Records": [{"messageId": "m1", "body": json.dumps(eb_event)}]}


def test_transcode_success(aws):
    s3, dynamodb = aws
    upload_key = "users/user-abc/uploads/req-001/hands.txt"
    s3.put_object(Bucket=BUCKET, Key=upload_key, Body=FIXTURE.read_bytes())

    table = dynamodb.Table(TABLE)
    table.put_item(Item={"userId": "user-abc", "jobId": "req-001", "status": "pending"})

    result = handler.lambda_handler(_sqs_event(BUCKET, upload_key), None)
    assert result["statusCode"] == 200

    transcoded = s3.get_object(Bucket=BUCKET, Key="users/user-abc/transcoded/req-001/hands.json")
    hands = json.loads(transcoded["Body"].read())
    assert isinstance(hands, list)
    assert len(hands) > 0
    assert "game_number" in hands[0]

    item = table.get_item(Key={"userId": "user-abc", "jobId": "req-001"})["Item"]
    assert item["status"] == "completed"
    assert item["transcodedKey"] == "users/user-abc/transcoded/req-001/hands.json"


def test_transcode_failure_updates_dynamodb_and_raises(aws):
    s3, dynamodb = aws
    missing_key = "users/user-xyz/uploads/req-002/missing.txt"

    table = dynamodb.Table(TABLE)
    table.put_item(Item={"userId": "user-xyz", "jobId": "req-002", "status": "pending"})

    with pytest.raises(Exception):
        handler.lambda_handler(_sqs_event(BUCKET, missing_key), None)

    item = table.get_item(Key={"userId": "user-xyz", "jobId": "req-002"})["Item"]
    assert item["status"] == "failed"
    assert "errorMessage" in item


def test_transcode_parses_user_id_and_request_id_from_key(aws):
    s3, dynamodb = aws
    upload_key = "users/64f8d438-e061/uploads/aabb1122/my file.txt"
    s3.put_object(Bucket=BUCKET, Key=upload_key, Body=FIXTURE.read_bytes())

    table = dynamodb.Table(TABLE)
    table.put_item(Item={"userId": "64f8d438-e061", "jobId": "aabb1122", "status": "pending"})

    handler.lambda_handler(_sqs_event(BUCKET, upload_key), None)

    transcoded = s3.get_object(Bucket=BUCKET, Key="users/64f8d438-e061/transcoded/aabb1122/my file.json")
    assert transcoded["Body"].read()

    item = table.get_item(Key={"userId": "64f8d438-e061", "jobId": "aabb1122"})["Item"]
    assert item["status"] == "completed"
    assert item["transcodedKey"] == "users/64f8d438-e061/transcoded/aabb1122/my file.json"
