"""Unit tests for the presigned upload URL Lambda handler."""
import json
import sys
import uuid
from pathlib import Path
from typing import Optional
from unittest.mock import MagicMock, patch

import pytest

# Import handler from Terraform-packaged Lambda code
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "terraform" / "lambda" / "api_handlers"))
import api_handlers


def _upload_event(user_id: str = "user-123", body: Optional[dict] = None) -> dict:
    return {
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": user_id,
                }
            }
        },
        "body": json.dumps(body) if body is not None else None,
    }


@patch.dict("os.environ", {"POKERHANDS_BUCKET": "pokerhands", "POKERHANDS_JOBS_TABLE": "pokerhands-jobs"})
@patch("api_handlers.boto3")
def test_upload_handler_returns_presigned_url_and_job_id(mock_boto3):
    mock_s3 = MagicMock()
    mock_boto3.client.return_value = mock_s3
    mock_s3.generate_presigned_url.return_value = "https://presigned.example/put"
    mock_dynamodb = MagicMock()
    mock_boto3.resource.return_value = mock_dynamodb
    mock_table = MagicMock()
    mock_dynamodb.Table.return_value = mock_table

    event = _upload_event(user_id="user-456", body={"filename": "my-hands.txt"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="aabbccdd11223344")):
        result = api_handlers.upload_handler(event, None)

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert "uploadUrl" in body
    assert body["uploadUrl"] == "https://presigned.example/put"
    assert "jobId" in body
    assert body["jobId"] == "aabbccdd11223344"

    mock_table.put_item.assert_called_once()
    call_kw = mock_table.put_item.call_args[1]
    item = call_kw["Item"]
    assert item["userId"] == "user-456"
    assert item["jobId"] == "aabbccdd11223344"
    assert item["status"] == "pending"
    assert "uploadKey" in item
    assert item["uploadKey"].endswith("my-hands.txt")
    assert "users/user-456/uploads/aabbccdd11223344/" in item["uploadKey"]


@patch.dict("os.environ", {"POKERHANDS_BUCKET": "pokerhands", "POKERHANDS_JOBS_TABLE": "pokerhands-jobs"})
@patch("api_handlers.boto3")
def test_upload_handler_uses_only_jwt_user_id_not_body(mock_boto3):
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://presigned.example/put"
    mock_boto3.client.return_value = mock_s3
    mock_table = MagicMock()
    mock_boto3.resource.return_value.Table.return_value = mock_table

    # Body might contain a different userId – must be ignored
    event = _upload_event(user_id="real-user-from-jwt", body={"userId": "attacker", "filename": "x.txt"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="job111")):
        api_handlers.upload_handler(event, None)

    call_kw = mock_table.put_item.call_args[1]
    assert call_kw["Item"]["userId"] == "real-user-from-jwt"
    assert "users/real-user-from-jwt/" in call_kw["Item"]["uploadKey"]


@patch.dict("os.environ", {"POKERHANDS_BUCKET": "pokerhands", "POKERHANDS_JOBS_TABLE": "pokerhands-jobs"})
@patch("api_handlers.boto3")
def test_upload_handler_sanitizes_filename(mock_boto3):
    mock_s3 = MagicMock()
    mock_s3.generate_presigned_url.return_value = "https://presigned.example/put"
    mock_boto3.client.return_value = mock_s3
    mock_table = MagicMock()
    mock_boto3.resource.return_value.Table.return_value = mock_table

    event = _upload_event(user_id="u1", body={"filename": "../../../etc/passwd"})
    with patch.object(uuid, "uuid4", return_value=MagicMock(hex="job222")):
        api_handlers.upload_handler(event, None)

    call_kw = mock_table.put_item.call_args[1]
    key = call_kw["Item"]["uploadKey"]
    assert ".." not in key
    assert "etc" not in key or "passwd" not in key
    assert "users/u1/uploads/job222/" in key
