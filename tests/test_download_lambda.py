import json
import os
import sys
from pathlib import Path

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


def _download_event(user_id="user-123", query_params=None):
    return {
        "requestContext": {"authorizer": {"claims": {"sub": user_id}}},
        "queryStringParameters": query_params,
    }


def test_download_handler_returns_presigned_get_url(aws):
    s3, dynamodb = aws
    table = dynamodb.Table(TABLE)
    table.put_item(Item={
        "userId": "user-abc",
        "jobId": "job-001",
        "transcodedKey": "users/user-abc/transcoded/job-001/hands.json",
        "status": "completed",
    })
    s3.put_object(Bucket=BUCKET, Key="users/user-abc/transcoded/job-001/hands.json", Body=b"[]")

    result = api_handlers.download_handler(
        _download_event(user_id="user-abc", query_params={"jobId": "job-001"}),
        None,
    )

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert "downloadUrl" in body
    assert "user-abc/transcoded/job-001/hands.json" in body["downloadUrl"]


def test_download_handler_verifies_ownership(aws):
    _, dynamodb = aws
    table = dynamodb.Table(TABLE)
    table.put_item(Item={
        "userId": "other-user",
        "jobId": "job-002",
        "transcodedKey": "users/other-user/transcoded/job-002/hands.json",
        "status": "completed",
    })

    result = api_handlers.download_handler(
        _download_event(user_id="attacker", query_params={"jobId": "job-002"}),
        None,
    )

    assert result["statusCode"] == 404


def test_download_handler_returns_404_for_missing_item(aws):
    result = api_handlers.download_handler(
        _download_event(user_id="user-abc", query_params={"jobId": "nonexistent"}),
        None,
    )
    assert result["statusCode"] == 404


def test_download_handler_returns_400_without_job_id(aws):
    result = api_handlers.download_handler(
        _download_event(user_id="user-abc", query_params=None),
        None,
    )
    assert result["statusCode"] == 400


def test_download_handler_returns_401_without_user_id(aws):
    event = {"requestContext": {"authorizer": {"claims": {}}}, "queryStringParameters": {"jobId": "j1"}}
    result = api_handlers.download_handler(event, None)
    assert result["statusCode"] == 401


def test_download_handler_returns_409_when_not_completed(aws):
    _, dynamodb = aws
    table = dynamodb.Table(TABLE)
    table.put_item(Item={"userId": "user-abc", "jobId": "job-003", "status": "pending"})

    result = api_handlers.download_handler(
        _download_event(user_id="user-abc", query_params={"jobId": "job-003"}),
        None,
    )
    assert result["statusCode"] == 409
