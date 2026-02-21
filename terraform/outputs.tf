output "pokerhands_bucket_name" {
  description = "Name of the pokerhands S3 bucket"
  value       = aws_s3_bucket.pokerhands.id
}

output "pokerhands_bucket_arn" {
  description = "ARN of the pokerhands S3 bucket"
  value       = aws_s3_bucket.pokerhands.arn
}

output "pokerhands_jobs_table_name" {
  description = "Name of the DynamoDB table for job/file metadata"
  value       = aws_dynamodb_table.pokerhands_jobs.name
}

output "pokerhands_jobs_table_arn" {
  description = "ARN of the DynamoDB table for job/file metadata"
  value       = aws_dynamodb_table.pokerhands_jobs.arn
}

# Custom domain: point api.allansattelbergrivera.com (CNAME or A/ALIAS) to this target.
output "api_gateway_domain_target" {
  description = "API Gateway regional domain name; point api_domain DNS (CNAME or A/ALIAS) here"
  value       = try(aws_api_gateway_domain_name.hand_history[0].regional_domain_name, null)
}
