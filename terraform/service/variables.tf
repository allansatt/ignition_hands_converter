variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for API Gateway authorizer and JWT validation (existing pool; supplied at deploy time)"
  type        = string
  default     = "us-east-1_t99BmzOa5"
}

variable "cognito_region" {
  description = "AWS region where the Cognito User Pool lives (used for issuer/authorizer; defaults to aws_region)"
  type        = string
  default     = null
}

variable "api_domain" {
  description = "Legacy: main API domain (e.g. api.allansattelbergrivera.com); hand-history API uses hand_history_api_domain instead"
  type        = string
  default     = "api.allansattelbergrivera.com"
}

variable "hand_history_api_domain" {
  description = "Custom domain for the hand-history API (e.g. hand-history.allansattelbergrivera.com; use cert *.allansattelbergrivera.com)"
  type        = string
  default     = "hand-history.allansattelbergrivera.com"
}

variable "hand_history_domain_cert" {
  description = "ACM certificate domain for hand_history_api_domain (e.g. *.allansattelbergrivera.com)"
  type        = string
  default     = "*.allansattelbergrivera.com"
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone name (e.g. allansattelbergrivera.com)"
  type        = string
  default     = "allansattelbergrivera.com"
}

variable "transcode_dlq_max_receive_count" {
  description = "Max receive count for the transcode queue before messages are sent to the DLQ"
  type        = number
  default     = 3
}
