locals {
  lambda_functions = {
    events        = module.events_lambda.function_name
    registrations = module.registrations_lambda.function_name
  }
}

# ---------- SNS topic (no subscription) ----------
resource "aws_sns_topic" "alarms" {
  name = "event-ticketing-alarms"
}

resource "aws_sns_topic_subscription" "alarms_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = "quincycudjoe1@gmail.com"
}

# ---------- Errors alarms ----------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_functions

  alarm_name          = "${each.value}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# ---------- Throttles alarms ----------
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = local.lambda_functions

  alarm_name          = "${each.value}-throttles"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# ---------- REGISTRATION_FAILED metric filter + alarm ----------
resource "aws_cloudwatch_log_metric_filter" "registration_failed" {
  name           = "RegistrationFailed"
  log_group_name = "/aws/lambda/${module.registrations_lambda.function_name}"
  pattern        = "REGISTRATION_FAILED"

  metric_transformation {
    name      = "RegistrationFailedCount"
    namespace = "EventTicketing"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "registration_failed" {
  alarm_name          = "registrations-handler-registration-failed"
  namespace           = "EventTicketing"
  metric_name         = "RegistrationFailedCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
