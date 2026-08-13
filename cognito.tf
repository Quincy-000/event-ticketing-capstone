locals {
  frontend_url = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

resource "aws_cognito_user_pool" "event_ticketing_users" {
  name                     = "event-ticketing-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = false
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = { Project = "event-ticketing-system" }
}

resource "aws_cognito_user_pool_client" "web_client" {
  name         = "web-client"
  user_pool_id = aws_cognito_user_pool.event_ticketing_users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows                  = ["implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [local.frontend_url, "http://localhost:8000"]
  logout_urls   = [local.frontend_url, "http://localhost:8000"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "event-ticketing-quincy000"
  user_pool_id = aws_cognito_user_pool.event_ticketing_users.id
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.this.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.event_ticketing_users.arn]
  identity_source = "method.request.header.Authorization"
}
