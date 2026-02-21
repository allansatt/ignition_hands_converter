variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for API Gateway authorizer and JWT validation (existing pool; supplied at deploy time)"
  type        = string
}

variable "cognito_region" {
  description = "AWS region where the Cognito User Pool lives (used for issuer/authorizer; defaults to aws_region)"
  type        = string
  default     = null
}

variable "api_domain" {
  description = "Custom domain for the API (e.g. api.allansattelbergrivera.com); used for API Gateway custom domain and base path mapping"
  type        = string
  default     = "api.allansattelbergrivera.com"
}

variable "api_domain_acm_certificate_arn" {
  description = "ARN of the existing ACM certificate for api_domain (optional; if not set, a data source lookup by domain is used)"
  type        = string
  default     = null
}

variable "transcode_dlq_max_receive_count" {
  description = "Max receive count for the transcode queue before messages are sent to the DLQ"
  type        = number
  default     = 3
}
