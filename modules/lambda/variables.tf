variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "source_dir" {
  description = "Path to the folder containing handler.py"
  type        = string
}

variable "handler" {
  description = "Entry point, e.g. handler.handler"
  type        = string
  default     = "handler.handler"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "environment_variables" {
  description = "Env vars exposed to the function (e.g. table names)"
  type        = map(string)
  default     = {}
}

variable "iam_policy_statements" {
  description = "List of least-privilege IAM statements for THIS function only"
  type = list(object({
    actions   = list(string)
    resources = list(string)
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}
