# Local runs only. Copy to backend.hcl (git-ignored) and fill in from
# `terraform -chdir=infra/bootstrap output tfstate`.
resource_group_name  = "wiz-ex-auea-bootstrap-rg"
storage_account_name = "wizexaueatfstxxxxx"
container_name       = "tfstate"
