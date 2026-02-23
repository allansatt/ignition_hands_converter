resource "aws_cloudwatch_event_rule" "s3_upload_to_transcode" {
  name        = "pokerhands-s3-upload-to-transcode"
  description = "Route S3 object-created events (uploads prefix) to transcode SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.pokerhands.id]
      }
      object = {
        key = [{ prefix = "users/" }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "transcode_queue" {
  rule      = aws_cloudwatch_event_rule.s3_upload_to_transcode.name
  target_id = "TranscodeQueue"
  arn       = aws_sqs_queue.transcode_queue.arn
}
