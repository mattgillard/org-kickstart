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

# We don't manage the payer via Terraform, but here it is anyway
resource "aws_organizations_account" "payer" {
  name      = var.payer_name
  email     = var.payer_email
  parent_id = aws_organizations_organizational_unit.governance_ou.id
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "aws_ssoadmin_account_assignment" "payer_account_group_assignment" {
  count              = var.disable_sso_management == true ? 0 : 1
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin_permission_set[0].arn
  principal_id       = aws_identitystore_group.admin_group[0].group_id
  principal_type     = "GROUP"
  target_id          = aws_organizations_account.payer.id
  target_type        = "AWS_ACCOUNT"
  provider = aws.sydney
}

resource "aws_account_primary_contact" "primary" {
  count              = var.global_primary_contact != null ? 1 : 0
  full_name          = var.global_primary_contact["full_name"]
  company_name       = lookup(var.global_primary_contact, "company_name", null)
  address_line_1     = var.global_primary_contact["address_line_1"]
  address_line_2     = lookup(var.global_primary_contact, "address_line_2", null)
  address_line_3     = lookup(var.global_primary_contact, "address_line_3", null)
  city               = var.global_primary_contact["city"]
  district_or_county = lookup(var.global_primary_contact, "district_or_county", null)
  state_or_region    = lookup(var.global_primary_contact, "state_or_region", null)
  postal_code        = var.global_primary_contact["postal_code"]
  country_code       = var.global_primary_contact["country_code"]
  phone_number       = var.global_primary_contact["phone_number"]
  website_url        = lookup(var.global_primary_contact, "website_url", null)
}

resource "aws_account_alternate_contact" "billing" {
  count                  = var.global_billing_contact != null ? 1 : 0
  alternate_contact_type = "BILLING"
  name                   = var.global_billing_contact["name"]
  title                  = var.global_billing_contact["title"]
  email_address          = var.global_billing_contact["email_address"]
  phone_number           = var.global_billing_contact["phone_number"]
}

resource "aws_account_alternate_contact" "security" {
  count                  = var.global_security_contact != null ? 1 : 0
  alternate_contact_type = "SECURITY"
  name                   = var.global_security_contact["name"]
  title                  = var.global_security_contact["title"]
  email_address          = var.global_security_contact["email_address"]
  phone_number           = var.global_security_contact["phone_number"]
}

resource "aws_account_alternate_contact" "operations" {
  count                  = var.global_operations_contact != null ? 1 : 0
  alternate_contact_type = "OPERATIONS"
  name                   = var.global_operations_contact["name"]
  title                  = var.global_operations_contact["title"]
  email_address          = var.global_operations_contact["email_address"]
  phone_number           = var.global_operations_contact["phone_number"]
}
