# Copyright 2026 Matt Gillard
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Amazon Inspector in this region, delegated to the security account. Opt in with
# security_services.disable_inspector = false.
#
# This uses the inspector2 resources available in AWS provider 5.x. Provider >= 6.23 can
# instead attach an INSPECTOR_POLICY at the org root, which is what upstream's
# sec_hub_2_support branch does; reconcile with that when it lands.

variable "inspector_resource_types" {
  description = "Inspector scan types to enable for all accounts: any of EC2, ECR, LAMBDA, LAMBDA_CODE."
  type        = list(string)
  default     = ["EC2", "ECR"]
}

variable "inspector_account_resource_types" {
  description = <<-EOT
    Per-account overrides of inspector_resource_types for existing member accounts, as a map
    of account ID => scan types. For example, skip ECR in an account whose images are
    replicated from one that is already scanned: { "111111111111" = ["EC2"] }.
  EOT
  type        = map(list(string))
  default     = {}
}

locals {
  enable_inspector = !tobool(local.security_services["disable_inspector"])

  # Every active org account except the security account (the delegated admin), including
  # the management account.
  inspector_member_ids = local.enable_inspector ? toset([
    for account in data.aws_organizations_organizational_unit_descendant_accounts.accounts.accounts :
    account.id if account.id != var.security_account_id && account.status == "ACTIVE"
  ]) : toset([])

  inspector_member_types = {
    for id in local.inspector_member_ids :
    id => sort(lookup(var.inspector_account_resource_types, id, var.inspector_resource_types))
  }
}

# Delegating the same account in several regions at once can fail with "Multiple changes
# cannot be done at the same time"; re-running the apply completes the remaining regions.
resource "aws_inspector2_delegated_admin_account" "inspector" {
  count      = local.enable_inspector ? 1 : 0
  provider   = aws.payer_account
  account_id = var.security_account_id
}

# Covers accounts that join the organization later.
resource "aws_inspector2_organization_configuration" "inspector" {
  count    = local.enable_inspector ? 1 : 0
  provider = aws.security_account
  # UpdateOrganizationConfiguration fails with "Invoking account is not enabled" until
  # Inspector is enabled in the delegated admin account itself.
  depends_on = [aws_inspector2_enabler.security_account]

  auto_enable {
    ec2         = contains(var.inspector_resource_types, "EC2")
    ecr         = contains(var.inspector_resource_types, "ECR")
    lambda      = contains(var.inspector_resource_types, "LAMBDA")
    lambda_code = contains(var.inspector_resource_types, "LAMBDA_CODE")
  }
}

data "aws_caller_identity" "payer" {
  provider = aws.payer_account
}

# AssociateMember rejects the management account ("your organization master must first enable
# Inspector to be added as a member") until it has enabled Inspector itself.
#
# Create-only bootstrap: once associated, the management account is a member, and only the
# delegated administrator can disable a member's scans. aws_inspector2_enabler.member owns its
# scan types from then on; ignore_changes stops this resource calling Disable with the
# management account's own credentials. Its delete would do the same, so before turning
# Inspector off, `terraform state rm` this resource.
resource "aws_inspector2_enabler" "payer" {
  count          = contains(local.inspector_member_ids, data.aws_caller_identity.payer.account_id) ? 1 : 0
  provider       = aws.payer_account
  depends_on     = [aws_inspector2_delegated_admin_account.inspector]
  account_ids    = [data.aws_caller_identity.payer.account_id]
  resource_types = local.inspector_member_types[data.aws_caller_identity.payer.account_id]

  timeouts {
    create = "15m"
  }

  lifecycle {
    ignore_changes = all
  }
}

# Auto-enable does not reach accounts that already exist, so associate and enable them here.
resource "aws_inspector2_member_association" "member" {
  for_each   = local.inspector_member_ids
  provider   = aws.security_account
  depends_on = [aws_inspector2_delegated_admin_account.inspector, aws_inspector2_enabler.payer]
  account_id = each.key
}

# The enabler accepts either the delegated admin or member accounts, not both.
resource "aws_inspector2_enabler" "security_account" {
  count          = local.enable_inspector ? 1 : 0
  provider       = aws.security_account
  depends_on     = [aws_inspector2_delegated_admin_account.inspector]
  account_ids    = [var.security_account_id]
  resource_types = var.inspector_resource_types

  # Enabling EC2 scanning has taken about 10 minutes; the provider default is 5.
  timeouts {
    create = "15m"
    update = "15m"
  }
}

# One enabler per account. Enablers that share accounts are unsafe: removing an account from
# an enabler disables all of its scan types, and Terraform does not order that against the
# enabler that adds it, so moving an account between them could leave it with no scanning.
#
# Creating an enabler also disables any types not listed, which removes what auto-enable gave
# an account with an override when it was associated.
resource "aws_inspector2_enabler" "member" {
  for_each       = local.inspector_member_types
  provider       = aws.security_account
  depends_on     = [aws_inspector2_member_association.member]
  account_ids    = [each.key]
  resource_types = each.value

  timeouts {
    create = "15m"
    update = "15m"
  }
}

# Replaced by aws_inspector2_enabler.member. Forget the old grouped enablers rather than
# destroying them, because their delete would disable Inspector for every account in them.
removed {
  from = aws_inspector2_enabler.members

  lifecycle {
    destroy = false
  }
}
