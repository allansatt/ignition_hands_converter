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
