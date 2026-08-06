output "table_name" {
  value = aws_dynamodb_table.this.name
}

output "table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "table_stream_arn" {
  value       = aws_dynamodb_table.this.stream_arn
  description = "Null unless streams are enabled; reserved for later if you wire up promote-on-cancel via DynamoDB Streams instead of inline Lambda logic"
}
