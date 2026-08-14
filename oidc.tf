resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # IAM caps the thumbprint list at 4 entries. Keep the live TLS leaf, the
  # new JWKS signing cert, and the two historical GitHub thumbprints.
  thumbprint_list = [
    "227203b5317f3818cab5b5ce596132bf36748c0e",
    "ca435a638a8cfed6b89364e064e08460b91c6250",
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
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
          # GitHub's immutable-IDs feature appends numeric owner/repo IDs to
          # the sub (verified from the live token claims, 2026-08-14):
          # repo:owner@<ownerId>/repo@<repoId>:environment:production
          "token.actions.githubusercontent.com:sub" = [
            "repo:Quincy-000@109243447/event-ticketing-capstone@1325355614:environment:production",
          ]
        }
      }
    }]
  })

  # The CD role runs `terraform apply` (infra + Lambda code) and syncs the
  # frontend. Scope: one statement per service the stack manages — broad
  # within each service, nothing outside them.
  inline_policy {
    name = "cd-deploy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "TerraformManagedServices"
          Effect = "Allow"
          Action = [
            "apigateway:*", "lambda:*", "dynamodb:*", "s3:*",
            "cognito-idp:*", "cloudfront:*", "iam:*", "sns:*",
            "cloudwatch:*", "logs:*", "budgets:*",
          ]
          Resource = ["*"]
        },
        {
          Sid      = "TerraformBasics"
          Effect   = "Allow"
          Action   = ["sts:GetCallerIdentity"]
          Resource = ["*"]
        },
      ]
    })
  }
}

output "cd_role_arn" {
  value = aws_iam_role.cd.arn
}
