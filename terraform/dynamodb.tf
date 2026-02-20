# DynamoDB table for job/file metadata.
#
# Used by: upload URL Lambda (write pending job), transcode Lambda (update with
# transcoded key and status), list API (query base table by userId; sort by createdAt in app),
# download URL Lambda (lookup transcoded key by userId + jobId).
# GSI jobId-index: partition key jobId only (lookups by job id).

resource "aws_dynamodb_table" "pokerhands_jobs" {
  name         = "pokerhands-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "jobId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "jobId"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "N"
  }

  global_secondary_index {
    name            = "jobId-index"
    hash_key        = "jobId"
    projection_type = "ALL"
  }

  tags = {
    Purpose = "Poker hand history job and file metadata"
  }
}
