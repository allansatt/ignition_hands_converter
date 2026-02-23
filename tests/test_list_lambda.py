import json
import os
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "terraform" / "service" / "lambda" / "api_handlers"))
import api_handlers

TABLE = "pokerhands-jobs"


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("POKERHANDS_BUCKET", "pokerhands")
    monkeypatch.setenv("POKERHANDS_JOBS_TABLE", TABLE)

    with mock_aws():
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

        yield dynamodb


def _list_event(user_id="user-123", query_params=None):
    return {
        "requestContext": {"authorizer": {"claims": {"sub": user_id}}},
        "queryStringParameters": query_params,
    }


def test_list_handler_returns_items_sorted_newest_first(aws):
    table = aws.Table(TABLE)
    table.put_item(Item={"userId": "u1", "jobId": "j1", "uploadKey": "users/u1/uploads/j1/old.txt", "status": "completed", "createdAt": 1000})
    table.put_item(Item={"userId": "u1", "jobId": "j2", "uploadKey": "users/u1/uploads/j2/new.txt", "status": "pending", "createdAt": 2000})

    result = api_handlers.list_handler(_list_event(user_id="u1"), None)
    assert result["statusCode"] == 200

    body = json.loads(result["body"])
    items = body["items"]
    assert len(items) == 2
    assert items[0]["jobId"] == "j2"
    assert items[1]["jobId"] == "j1"

    for item in items:
        assert "displayName" in item
        assert "jobId" in item
        assert "status" in item
        assert "createdAt" in item


def test_list_handler_queries_by_jwt_user_id_only(aws):
    table = aws.Table(TABLE)
    table.put_item(Item={"userId": "real-user", "jobId": "j1", "uploadKey": "users/real-user/uploads/j1/a.txt", "status": "completed", "createdAt": 1000})
    table.put_item(Item={"userId": "other-user", "jobId": "j2", "uploadKey": "users/other-user/uploads/j2/b.txt", "status": "completed", "createdAt": 2000})

    result = api_handlers.list_handler(_list_event(user_id="real-user"), None)
    body = json.loads(result["body"])

    assert len(body["items"]) == 1
    assert body["items"][0]["jobId"] == "j1"


def test_list_handler_supports_pagination(aws):
    table = aws.Table(TABLE)
    table.put_item(Item={"userId": "u1", "jobId": "j1", "uploadKey": "users/u1/uploads/j1/a.txt", "status": "completed", "createdAt": 1000})
    table.put_item(Item={"userId": "u1", "jobId": "j2", "uploadKey": "users/u1/uploads/j2/b.txt", "status": "completed", "createdAt": 2000})

    result = api_handlers.list_handler(_list_event(user_id="u1", query_params={"limit": "1"}), None)
    body = json.loads(result["body"])

    assert len(body["items"]) == 1
    assert "nextToken" in body


def test_list_handler_returns_401_without_user_id(aws):
    event = {"requestContext": {"authorizer": {"claims": {}}}}
    result = api_handlers.list_handler(event, None)
    assert result["statusCode"] == 401
