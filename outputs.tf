output "name" {
  description = "The name of the pipeline."
  value       = local.pipeline_name
}

output "id" {
  description = "The codepipeline ID."
  value       = aws_codepipeline.this.id
}

output "arn" {
  description = "The codepipeline ARN."
  value       = aws_codepipeline.this.arn
}

output "tags_all" {
  description = "All tags applied to the pipeline."
  value       = aws_codepipeline.this.arn
}