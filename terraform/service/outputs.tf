output "pokerhands_bucket_name" {
  value = aws_s3_bucket.pokerhands.id
}

output "pokerhands_bucket_arn" {
  value = aws_s3_bucket.pokerhands.arn
}

output "pokerhands_jobs_table_name" {
  value = aws_dynamodb_table.pokerhands_jobs.name
}

output "pokerhands_jobs_table_arn" {
  value = aws_dynamodb_table.pokerhands_jobs.arn
}

output "hand_history_api_domain_target" {
  value = aws_api_gateway_domain_name.hand_history.regional_domain_name
}
