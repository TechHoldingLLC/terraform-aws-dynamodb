#########################
#  dynamodb/outputs.tf  #
#########################

output "arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.db.arn
}

output "id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.db.id
}

output "stream_arn" {
  description = "The ARN of the Table Stream. Only available when var.stream_enabled is true"
  value       = var.stream_enabled ? aws_dynamodb_table.db.stream_arn : null
}

output "stream_label" {
  description = "A timestamp, in ISO 8601 format of the Table Stream. Only available when var.stream_enabled is true"
  value       = var.stream_enabled ? aws_dynamodb_table.db.stream_label : null
}
