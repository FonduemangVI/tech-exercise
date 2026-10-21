variable "subscription_id" {
  description = "Azure subscription ID provided by CloudLabs."
  type        = string
}

variable "location" {
  description = "Azure region, e.g. australiaeast. Must match the bootstrap."
  type        = string
}

variable "location_short" {
  description = "Short region code used in names, e.g. auea. Must match the bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_short))
    error_message = "location_short must be 2 to 6 lowercase letters or digits."
  }
}

variable "owner_tag" {
  description = "Value for the Owner tag."
  type        = string
}

variable "github_repository" {
  description = "owner/repo, used in the Repo tag."
  type        = string
  default     = "FonduemangVI/tech-exercise"
}

variable "log_retention_days" {
  description = "Log Analytics retention. 30 days is included in the base price."
  type        = number
  default     = 30
}

variable "law_daily_quota_gb" {
  description = "Daily ingestion cap for Log Analytics, to control cost. Data above the cap is dropped until the next day."
  type        = number
  default     = 1
}
