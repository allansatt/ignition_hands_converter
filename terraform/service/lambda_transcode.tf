resource "null_resource" "build_transcode_lambda" {
  triggers = {
    handler  = filemd5("${path.module}/lambda/transcode/handler.py")
    convert  = filemd5("${path.module}/../../src/convert.py")
    build_sh = filemd5("${path.module}/lambda/transcode/build.sh")
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/lambda/transcode/build.sh"
    working_dir = path.module
  }
}

resource "aws_lambda_function" "transcode" {
  filename         = "${path.module}/lambda/transcode/deployment.zip"
  function_name    = "pokerhands-transcode"
  role             = aws_iam_role.lambda_transcode.arn
  handler          = "handler.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/transcode/deployment.zip")
  runtime          = "python3.12"

  environment {
    variables = {
      POKERHANDS_BUCKET     = aws_s3_bucket.pokerhands.id
      POKERHANDS_JOBS_TABLE = aws_dynamodb_table.pokerhands_jobs.name
    }
  }

  depends_on = [null_resource.build_transcode_lambda]
}

resource "aws_lambda_event_source_mapping" "transcode_sqs" {
  event_source_arn = aws_sqs_queue.transcode_queue.arn
  function_name    = aws_lambda_function.transcode.function_name
  batch_size       = 1
}
