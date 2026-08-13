resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

resource "aws_iam_role" "cd" {
  name = "event-ticketing-cd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Quincy-000/event-ticketing-capstone:ref:refs/heads/main"
        }
      }
    }]
  })

  inline_policy {
    name = "cd-deploy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = [aws_s3_bucket.frontend.arn]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:DeleteObject"]
          Resource = ["${aws_s3_bucket.frontend.arn}/*"]
        },
        {
          Effect = "Allow"
          Action = ["lambda:UpdateFunctionCode"]
          Resource = [
            module.events_lambda.function_arn,
            module.registrations_lambda.function_arn,
          ]
        }
      ]
    })
  }
}

output "cd_role_arn" {
  value = aws_iam_role.cd.arn
}
