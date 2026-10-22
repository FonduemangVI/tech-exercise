# Copy to bootstrap.tfvars (git-ignored) and fill in.
subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "eastus" # the lab subscription only allows East US
location_short  = "eus"
github_owner    = "FonduemangVI"
github_repo     = "tech-exercise"
owner_tag       = "Michael Thomas"

# OIDC subject prefix with owner and repo IDs (immutable subjects). Fill in from:
# gh api repos/FonduemangVI/tech-exercise/actions/oidc/customization/sub --jq .sub_claim_prefix
github_oidc_subject_prefix = "repo:FonduemangVI@15520607/tech-exercise@1426612616"
