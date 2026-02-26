resource "aws_iam_role" "lambda_transcode" {
  name = "pokerhands-lambda-transcode"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_transcode" {
  name = "pokerhands-transcode"
  role = aws_iam_role.lambda_transcode.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "S3Pokerhands"
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject"
          ]
          Resource = "${aws_s3_bucket.pokerhands.arn}/*"
        },
        {
          Sid    = "DynamoDBJobs"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query",
            "dynamodb:BatchGetItem"
          ]
          Resource = [
            aws_dynamodb_table.pokerhands_jobs.arn,
            "${aws_dynamodb_table.pokerhands_jobs.arn}/index/*"
          ]
        },
        {
          Sid    = "LambdaBasic"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:*:*:*"
        }
      ],
      [
        {
          Sid    = "SQSTranscode"
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes"
          ]
          Resource = [aws_sqs_queue.transcode_queue.arn]
        }
      ]
    )
  })
}

resource "aws_iam_role" "lambda_upload_url" {
  name = "pokerhands-lambda-upload-url"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_upload_url" {
  name = "pokerhands-upload-url"
  role = aws_iam_role.lambda_upload_url.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3PresignedPut"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.pokerhands.arn}/*"
      },
      {
        Sid    = "DynamoDBJobs"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.pokerhands_jobs.arn
      },
      {
        Sid    = "LambdaBasic"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_list" {
  name = "pokerhands-lambda-list"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_list" {
  name = "pokerhands-list"
  role = aws_iam_role.lambda_list.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBQuery"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.pokerhands_jobs.arn,
          "${aws_dynamodb_table.pokerhands_jobs.arn}/index/*"
        ]
      },
      {
        Sid    = "LambdaBasic"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_download_url" {
  name = "pokerhands-lambda-download-url"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_download_url" {
  name = "pokerhands-download-url"
  role = aws_iam_role.lambda_download_url.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3PresignedGet"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.pokerhands.arn}/*"
      },
      {
        Sid    = "DynamoDBGetAndQuery"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          aws_dynamodb_table.pokerhands_jobs.arn,
          "${aws_dynamodb_table.pokerhands_jobs.arn}/index/*"
        ]
      },
      {
        Sid    = "LambdaBasic"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "allow_eventbridge_transcode" {
  queue_url = aws_sqs_queue.transcode_queue.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeTranscode"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.transcode_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_upload_to_transcode.arn
          }
        }
      }
    ]
  })
}
