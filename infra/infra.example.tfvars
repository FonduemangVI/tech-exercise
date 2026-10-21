# Local runs only. Copy to infra.tfvars (git-ignored) and fill in.
# The pipeline sets these as TF_VAR_ environment variables from repo variables.
subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "australiaeast"
location_short  = "auea"
owner_tag       = "Michael Thomas"
admin_object_id = "00000000-0000-0000-0000-000000000000"
admin_ip_cidrs  = ["203.0.113.10/32"]

# Placeholder: paste the full single line from ~/.ssh/wiz-exercise.pub
vm_ssh_public_key = "ssh-ed25519 AAAA... wiz-exercise-mongo-vm"
