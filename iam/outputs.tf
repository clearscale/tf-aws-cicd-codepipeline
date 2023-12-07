output "role" {
  description = "Service role information."
  value = {
    id          = aws_iam_role.this.id
    arn         = aws_iam_role.this.arn
    name        = aws_iam_role.this.name
    unique_id   = aws_iam_role.this.unique_id
    create_date = aws_iam_role.this.create_date
  }
}