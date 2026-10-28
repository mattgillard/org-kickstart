# Copyright 2023 Chris Farris <chris@primeharbor.com>
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

# The security account is special. It:
# * Holds the CloudTrail Bucket
# * Is trusted by all the other accounts for the security-audit role
# * Is delegated administrator for a number of security services

# For more about the security account, see:
# https://www.chrisfarris.com/post/securityaccount/
# https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/security-ou-and-accounts.html#security-tooling-accounts


# We explictly create a security account.
module "security_account" {
  source = "./modules/account"
  providers = {
    aws                 = aws
    aws.identity_center = aws.identity_center
  }

  account_name             = var.security_account_name
  account_email            = var.security_account_root_email
  parent_ou_id             = aws_organizations_organizational_unit.governance_ou.id
  disable_sso_management   = var.disable_sso_management
  admin_permission_set_arn = var.disable_sso_management ? null : aws_ssoadmin_permission_set.admin_permission_set[0].arn
  admin_group_id           = var.disable_sso_management ? null : aws_identitystore_group.admin_group[0].group_id
  billing_contact          = var.global_billing_contact
  security_contact         = var.global_security_contact
  operations_contact       = var.global_operations_contact
  primary_contact          = var.global_primary_contact
  additional_permission_sets = var.disable_sso_management ? {} : {
    for k, v in var.additional_permission_sets : k => {
      permission_set_arn = aws_ssoadmin_permission_set.additional_permission_sets[k].arn
      group_id           = aws_identitystore_group.additional_groups[k].group_id
    }
  }
}


# And delegate power to it


# resource "aws_organizations_delegated_administrator" "macie" {
#   account_id        = module.security_account.account_id
#   service_principal = "macie.amazonaws.com"
# }

# resource "aws_organizations_delegated_administrator" "inspector2" {
#   account_id        = module.security_account.account_id
#   service_principal = "inspector2.amazonaws.com"
# }

# resource "aws_organizations_delegated_administrator" "securityhub" {
#   account_id        = module.security_account.account_id
#   service_principal = "securityhub.amazonaws.com"
# }

resource "aws_organizations_delegated_administrator" "sso" {
  account_id        = module.security_account.account_id
  service_principal = "sso.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "cloudformation" {
  account_id        = module.security_account.account_id
  service_principal = "member.org.stacksets.cloudformation.amazonaws.com"
}

# Lets the security account create organization-wide analyzers. The analyzers are regional;
# create them with modules/access_analyzer once per region, after this module.
resource "aws_organizations_delegated_administrator" "access_analyzer" {
  count             = var.enable_access_analyzer ? 1 : 0
  account_id        = module.security_account.account_id
  service_principal = "access-analyzer.amazonaws.com"
  depends_on        = [aws_iam_service_linked_role.access_analyzer]
}

# CreateAnalyzer for an ORGANIZATION analyzer fails with "Access Analyzer Service Linked Role
# is not in the organizational management account" until this role exists in the payer. The
# console creates it implicitly; Terraform must create it. If it already exists, import it:
#   terraform import 'module.organization.aws_iam_service_linked_role.access_analyzer[0]' \
#     arn:aws:iam::<payer>:role/aws-service-role/access-analyzer.amazonaws.com/AWSServiceRoleForAccessAnalyzer
resource "aws_iam_service_linked_role" "access_analyzer" {
  count            = var.enable_access_analyzer ? 1 : 0
  aws_service_name = "access-analyzer.amazonaws.com"
}

