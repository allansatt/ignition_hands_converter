# API Gateway REST API: /hand-history routes (upload URL, list files, download URL), Cognito authorizer.
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
# REST API and /hand-history resource
# ---------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "hand_history" {
  name        = "pokerhands-hand-history"
  description = "Hand history upload, list, and download API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "hand_history" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_rest_api.hand_history.root_resource_id
  path_part   = "hand-history"
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
# POST /hand-history/upload-url
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_resource.hand_history.id
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
# GET /hand-history/files
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "files" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_resource.hand_history.id
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
# GET /hand-history/download (query: jobId)
# ---------------------------------------------------------------------------

resource "aws_api_gateway_resource" "download" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  parent_id   = aws_api_gateway_resource.hand_history.id
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
# Custom domain: https://api.allansattelbergrivera.com
# Reference existing ACM certificate via data source (or var.api_domain_acm_certificate_arn).
# DNS: Point api.allansattelbergrivera.com (CNAME or A/ALIAS) to the API Gateway regional domain (see output).
# ---------------------------------------------------------------------------

data "aws_acm_certificate" "api_domain" {
  count       = var.api_domain_acm_certificate_arn == null ? 1 : 0
  domain      = var.api_domain
  most_recent = true
  statuses    = ["ISSUED"]
}

locals {
  api_domain_cert_arn = coalesce(var.api_domain_acm_certificate_arn, try(data.aws_acm_certificate.api_domain[0].arn, null))
}

resource "aws_api_gateway_domain_name" "hand_history" {
  count = local.api_domain_cert_arn != null ? 1 : 0

  domain_name              = var.api_domain
  regional_certificate_arn  = local.api_domain_cert_arn
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "hand_history" {
  count = local.api_domain_cert_arn != null ? 1 : 0

  api_id      = aws_api_gateway_rest_api.hand_history.id
  stage_name  = aws_api_gateway_stage.hand_history.stage_name
  domain_name = aws_api_gateway_domain_name.hand_history[0].domain_name
}
