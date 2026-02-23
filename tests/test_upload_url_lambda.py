import json
import sys
import uuid
from pathlib import Path
from unittest.mock import patch, MagicMock

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "terraform" / "service" / "lambda" / "api_handlers"))
import api_handlers

BUCKET = "pokerhands"
TABLE = "pokerhands-jobs"


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


def _upload_event(user_id="user-123", body=None):
    return {
        "requestContext": {"authorizer": {"claims": {"sub": user_id}}},
        "body": json.dumps(body) if body is not None else None,
    }


def test_upload_handler_returns_presigned_url_and_job_id(aws):
    _, dynamodb = aws

    event = _upload_event(user_id="user-456", body={"filename": "my-hands.txt"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="aabbccdd11223344")):
        result = api_handlers.upload_handler(event, None)

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert "uploadUrl" in body
    assert body["jobId"] == "aabbccdd11223344"

    table = dynamodb.Table(TABLE)
    item = table.get_item(Key={"userId": "user-456", "jobId": "aabbccdd11223344"})["Item"]
    assert item["userId"] == "user-456"
    assert item["status"] == "pending"
    assert item["uploadKey"].endswith("my-hands.txt")
    assert "users/user-456/uploads/aabbccdd11223344/" in item["uploadKey"]


def test_upload_handler_uses_only_jwt_user_id_not_body(aws):
    _, dynamodb = aws

    event = _upload_event(user_id="real-user-from-jwt", body={"userId": "attacker", "filename": "x.txt"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="job111")):
        api_handlers.upload_handler(event, None)

    table = dynamodb.Table(TABLE)
    item = table.get_item(Key={"userId": "real-user-from-jwt", "jobId": "job111"})["Item"]
    assert item["userId"] == "real-user-from-jwt"
    assert "users/real-user-from-jwt/" in item["uploadKey"]


def test_upload_handler_sanitizes_filename(aws):
    _, dynamodb = aws

    event = _upload_event(user_id="u1", body={"filename": "../../../etc/passwd"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="job222")):
        api_handlers.upload_handler(event, None)

    table = dynamodb.Table(TABLE)
    item = table.get_item(Key={"userId": "u1", "jobId": "job222"})["Item"]
    assert ".." not in item["uploadKey"]
    assert "users/u1/uploads/job222/" in item["uploadKey"]
