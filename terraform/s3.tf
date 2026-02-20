# S3 bucket "pokerhands" for hand history uploads and transcoded outputs.
#
# Key layout (object key prefix convention; no physical folders are created):
#   - Uploads:  users/{userId}/uploads/{requestId}/{originalName}
#   - Outputs:  users/{userId}/transcoded/{requestId}/{outputName}

resource "aws_s3_bucket" "pokerhands" {
  bucket = "pokerhands"

  tags = {
    Purpose = "Poker hand history uploads and transcoded files"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pokerhands" {
  bucket = aws_s3_bucket.pokerhands.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "pokerhands" {
  bucket = aws_s3_bucket.pokerhands.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
