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

locals {
  enable_inspector = !tobool(local.security_services["disable_inspector"])

  # Every active org account except the security account (the delegated admin), including
  # the management account.
  inspector_member_ids = local.enable_inspector ? toset([
    for account in data.aws_organizations_organizational_unit_descendant_accounts.accounts.accounts :
    account.id if account.id != var.security_account_id && account.status == "ACTIVE"
  ]) : toset([])
}

resource "aws_inspector2_delegated_admin_account" "inspector" {
  count      = local.enable_inspector ? 1 : 0
  provider   = aws.payer_account
  account_id = var.security_account_id
}

# Covers accounts that join the organization later.
resource "aws_inspector2_organization_configuration" "inspector" {
  count      = local.enable_inspector ? 1 : 0
  provider   = aws.security_account
  depends_on = [aws_inspector2_delegated_admin_account.inspector]

  auto_enable {
    ec2         = contains(var.inspector_resource_types, "EC2")
    ecr         = contains(var.inspector_resource_types, "ECR")
    lambda      = contains(var.inspector_resource_types, "LAMBDA")
    lambda_code = contains(var.inspector_resource_types, "LAMBDA_CODE")
  }
}

# Auto-enable does not reach accounts that already exist, so associate and enable them here.
resource "aws_inspector2_member_association" "member" {
  for_each   = local.inspector_member_ids
  provider   = aws.security_account
  depends_on = [aws_inspector2_delegated_admin_account.inspector]
  account_id = each.key
}

# The enabler accepts either the delegated admin or member accounts, not both.
resource "aws_inspector2_enabler" "security_account" {
  count          = local.enable_inspector ? 1 : 0
  provider       = aws.security_account
  depends_on     = [aws_inspector2_delegated_admin_account.inspector]
  account_ids    = [var.security_account_id]
  resource_types = var.inspector_resource_types
}

resource "aws_inspector2_enabler" "members" {
  count          = length(local.inspector_member_ids) > 0 ? 1 : 0
  provider       = aws.security_account
  depends_on     = [aws_inspector2_member_association.member]
  account_ids    = local.inspector_member_ids
  resource_types = var.inspector_resource_types
}
