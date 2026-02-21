# SQS queue for transcode jobs; EventBridge will send S3 object-created events here,
# and the transcode Lambda is triggered via event source mapping (see EventBridge + Lambda tasks).
# DLQ holds messages that fail after max receive count for retry handling and inspection.

resource "aws_sqs_queue" "transcode_dlq" {
  name = "pokerhands-transcode-dlq"
}

resource "aws_sqs_queue" "transcode_queue" {
  name = "pokerhands-transcode-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transcode_dlq.arn
    maxReceiveCount     = var.transcode_dlq_max_receive_count
  })
}

output "transcode_queue_arn" {
  value = aws_sqs_queue.transcode_queue.arn
}

output "transcode_queue_url" {
  value = aws_sqs_queue.transcode_queue.url
}
