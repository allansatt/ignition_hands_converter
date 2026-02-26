# Run `bash lambda/transcode/build.sh` before `terraform apply`.
resource "aws_lambda_function" "transcode" {
  filename         = "${path.module}/lambda/transcode/deployment.zip"
  function_name    = "pokerhands-transcode"
  role             = aws_iam_role.lambda_transcode.arn
  handler          = "handler.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/transcode/deployment.zip")
  runtime          = "python3.12"
  timeout          = 10

  environment {
    variables = {
      POKERHANDS_BUCKET     = aws_s3_bucket.pokerhands.id
      POKERHANDS_JOBS_TABLE = aws_dynamodb_table.pokerhands_jobs.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "transcode_sqs" {
  event_source_arn = aws_sqs_queue.transcode_queue.arn
  function_name    = aws_lambda_function.transcode.function_name
  batch_size       = 1
}
