# API Gateway REST API: /upload-url, /files, /download (no /hand-history prefix). Cognito authorizer.
# Unauthenticated or invalid tokens receive 401 (Cognito authorizer default).

# ---------------------------------------------------------------------------
# Stub Lambdas for the three endpoints (implementation in later tasks)
# ---------------------------------------------------------------------------

data "archive_file" "api_handlers" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/api_handlers"
  output_path = "${path.module}/lambda/api_handlers.zip"
}

resource "aws_lambda_function" "upload_url" {
  filename         = data.archive_file.api_handlers.output_path
  function_name    = "pokerhands-upload-url"
  role             = aws_iam_role.lambda_upload_url.arn
  handler          = "api_handlers.upload_handler"
  source_code_hash = data.archive_file.api_handlers.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      POKERHANDS_BUCKET     = aws_s3_bucket.pokerhands.id
      POKERHANDS_JOBS_TABLE = aws_dynamodb_table.pokerhands_jobs.name
    }
  }
}

resource "aws_lambda_function" "list_files" {
  filename         = data.archive_file.api_handlers.output_path
  function_name    = "pokerhands-list-files"
  role             = aws_iam_role.lambda_list.arn
  handler          = "api_handlers.list_handler"
  source_code_hash = data.archive_file.api_handlers.output_base64sha256
  runtime          = "python3.12"
}

resource "aws_lambda_function" "download_url" {
  filename         = data.archive_file.api_handlers.output_path
  function_name    = "pokerhands-download-url"
  role             = aws_iam_role.lambda_download_url.arn
  handler          = "api_handlers.download_handler"
  source_code_hash = data.archive_file.api_handlers.output_base64sha256
  runtime          = "python3.12"
}

# ---------------------------------------------------------------------------
# REST API (paths at root: /upload-url, /files, /download)
# ---------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "hand_history" {
  name        = "pokerhands-hand-history"
  description = "Hand history upload, list, and download API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Cognito authorizer: invalid or missing token → 401
resource "aws_api_gateway_authorizer" "cognito" {
  rest_api_id          = aws_api_gateway_rest_api.hand_history.id
  name                 = "cognito-authorizer"
  type                 = "COGNITO_USER_POOLS"
  provider_arns        = [local.cognito_user_pool_arn]
}

locals {
  cognito_region       = coalesce(var.cognito_region, var.aws_region)
  cognito_user_pool_arn = "arn:aws:cognito-idp:${local.cognito_region}:${data.aws_caller_identity.current.account_id}:userpool/${var.cognito_user_pool_id}"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# POST /upload-url
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_rest_api.hand_history.root_resource_id
  path_part   = "upload-url"
}

resource "aws_api_gateway_method" "upload_url" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "upload_url" {
  rest_api_id             = aws_api_gateway_rest_api.hand_history.id
  resource_id              = aws_api_gateway_resource.upload_url.id
  http_method              = aws_api_gateway_method.upload_url.http_method
  type                     = "AWS_PROXY"
  integration_http_method  = "POST"
  uri                      = aws_lambda_function.upload_url.invoke_arn
}

resource "aws_lambda_permission" "upload_url" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hand_history.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# GET /files
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "files" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_rest_api.hand_history.root_resource_id
  path_part   = "files"
}

resource "aws_api_gateway_method" "list_files" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.files.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "list_files" {
  rest_api_id             = aws_api_gateway_rest_api.hand_history.id
  resource_id              = aws_api_gateway_resource.files.id
  http_method              = aws_api_gateway_method.list_files.http_method
  type                     = "AWS_PROXY"
  integration_http_method  = "POST"
  uri                      = aws_lambda_function.list_files.invoke_arn
}

resource "aws_lambda_permission" "list_files" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_files.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hand_history.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# GET /download (query: jobId)
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "download" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_rest_api.hand_history.root_resource_id
  path_part   = "download"
}

resource "aws_api_gateway_method" "download" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.download.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "download" {
  rest_api_id             = aws_api_gateway_rest_api.hand_history.id
  resource_id              = aws_api_gateway_resource.download.id
  http_method              = aws_api_gateway_method.download.http_method
  type                     = "AWS_PROXY"
  integration_http_method  = "POST"
  uri                      = aws_lambda_function.download_url.invoke_arn
}

resource "aws_lambda_permission" "download" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.download_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hand_history.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# Deployment (stage)
# ---------------------------------------------------------------------------

resource "aws_api_gateway_deployment" "hand_history" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  depends_on = [
    aws_api_gateway_integration.upload_url,
    aws_api_gateway_integration.list_files,
    aws_api_gateway_integration.download,
  ]
}

resource "aws_api_gateway_stage" "hand_history" {
  deployment_id = aws_api_gateway_deployment.hand_history.id
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  stage_name    = "prod"
}

# ---------------------------------------------------------------------------
# Custom domain: hand_history_api_domain (e.g. hand-history.api...) with ACM cert hand_history_domain_cert.
# Base path mapping at root so URLs are https://<domain>/upload-url, /files, /download.
# ---------------------------------------------------------------------------

data "aws_acm_certificate" "hand_history_domain" {
  domain      = var.hand_history_domain_cert
  most_recent = true
  statuses    = ["ISSUED"]
}

resource "aws_api_gateway_domain_name" "hand_history" {
  domain_name              = var.hand_history_api_domain
  regional_certificate_arn  = data.aws_acm_certificate.hand_history_domain.arn
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "hand_history" {
  api_id      = aws_api_gateway_rest_api.hand_history.id
  stage_name  = aws_api_gateway_stage.hand_history.stage_name
  domain_name = aws_api_gateway_domain_name.hand_history.domain_name
}

# ---------------------------------------------------------------------------
# Route53 A-alias record: hand-history.allansattelbergrivera.com → API GW
# ---------------------------------------------------------------------------

data "aws_route53_zone" "main" {
  name = var.hosted_zone_name
}

resource "aws_route53_record" "hand_history" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.hand_history_api_domain
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.hand_history.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.hand_history.regional_zone_id
    evaluate_target_health = false
  }
}
