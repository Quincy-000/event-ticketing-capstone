# ---------- AWS Budgets (cost tracking within Free Tier) ----------
# Brief requirement: "AWS Budgets (cost tracking within Free Tier)"
# $10/month hard ceiling with two alerts:
#   - FORECASTED > 80%  → warns before the month is overspent
#   - ACTUAL > 100%     → hard-stop alert the moment spend exceeds the budget

resource "aws_budgets_budget" "monthly" {
  name         = "event-ticketing-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["quincycudjoe1@gmail.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["quincycudjoe1@gmail.com"]
  }

  tags = { Project = "event-ticketing-system", Purpose = "cost-tracking" }
}
