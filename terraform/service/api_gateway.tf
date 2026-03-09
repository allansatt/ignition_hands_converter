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
  timeout          = 10

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
  timeout          = 10

  environment {
    variables = {
      POKERHANDS_BUCKET     = aws_s3_bucket.pokerhands.id
      POKERHANDS_JOBS_TABLE = aws_dynamodb_table.pokerhands_jobs.name
    }
  }
}

resource "aws_lambda_function" "download_url" {
  filename         = data.archive_file.api_handlers.output_path
  function_name    = "pokerhands-download-url"
  role             = aws_iam_role.lambda_download_url.arn
  handler          = "api_handlers.download_handler"
  source_code_hash = data.archive_file.api_handlers.output_base64sha256
  runtime          = "python3.12"
  timeout          = 10

  environment {
    variables = {
      POKERHANDS_BUCKET     = aws_s3_bucket.pokerhands.id
      POKERHANDS_JOBS_TABLE = aws_dynamodb_table.pokerhands_jobs.name
    }
  }
}

resource "aws_api_gateway_rest_api" "hand_history" {
  name        = "pokerhands-hand-history"
  description = "Hand history upload, list, and download API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [local.cognito_user_pool_arn]
  # Explicit token source; required for Bearer token in Authorization header
  identity_source = "method.request.header.Authorization"
}

locals {
  cognito_region       = coalesce(var.cognito_region, var.aws_region)
  cognito_user_pool_arn = "arn:aws:cognito-idp:${local.cognito_region}:${data.aws_caller_identity.current.account_id}:userpool/${var.cognito_user_pool_id}"
}

data "aws_caller_identity" "current" {}

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

# CORS preflight for /upload-url
resource "aws_api_gateway_method" "upload_url_options" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_url_options" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "upload_url_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "upload_url_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.upload_url_options.http_method
  status_code = aws_api_gateway_method_response.upload_url_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origin}'"
  }
}

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

# CORS preflight for /files
resource "aws_api_gateway_method" "files_options" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.files.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "files_options" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.files.id
  http_method = aws_api_gateway_method.files_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "files_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.files.id
  http_method = aws_api_gateway_method.files_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "files_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.files.id
  http_method = aws_api_gateway_method.files_options.http_method
  status_code = aws_api_gateway_method_response.files_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origin}'"
  }
}

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

# CORS preflight for /download
resource "aws_api_gateway_method" "download_options" {
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  resource_id   = aws_api_gateway_resource.download.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "download_options" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.download.id
  http_method = aws_api_gateway_method.download_options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "download_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.download.id
  http_method = aws_api_gateway_method.download_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "download_options_200" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  resource_id = aws_api_gateway_resource.download.id
  http_method = aws_api_gateway_method.download_options.http_method
  status_code = aws_api_gateway_method_response.download_options_200.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origin}'"
  }
}

resource "aws_api_gateway_deployment" "hand_history" {
  rest_api_id = aws_api_gateway_rest_api.hand_history.id
  depends_on = [
    aws_api_gateway_integration.upload_url,
    aws_api_gateway_integration.upload_url_options,
    aws_api_gateway_integration.list_files,
    aws_api_gateway_integration.files_options,
    aws_api_gateway_integration.download,
    aws_api_gateway_integration.download_options,
  ]
  # Force redeploy when authorizer or auth-related config changes; API Gateway
  # does not auto-redeploy on authorizer updates, which can cause stale 401s
  triggers = {
    redeployment = sha1(join(",", [
      aws_api_gateway_authorizer.cognito.id,
      local.cognito_user_pool_arn,
    ]))
  }
}

resource "aws_api_gateway_stage" "hand_history" {
  deployment_id = aws_api_gateway_deployment.hand_history.id
  rest_api_id   = aws_api_gateway_rest_api.hand_history.id
  stage_name    = "prod"
}

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
