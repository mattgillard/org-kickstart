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

# Account baseline for the management (payer) account.
#
# pht-account-configurator only runs on accounts created through CreateAccount, so it never
# configures the management account. This module applies the same controls to management,
# driven by the same account-factory-config.yaml, so one file defines both baselines. Each
# control is applied only when its config key is present, matching the Lambdas.
#
# default_vpc is deliberately not mirrored: rather than deleting the management account's
# default VPCs, the module strips all rules from their default security group.
#
# Call once per region with the payer provider for that region. Set
# manage_account_settings = true in exactly one call for the account-wide settings.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0"
    }
  }
}

variable "config" {
  description = "Decoded account-factory-config.yaml, e.g. yamldecode(file(\"account-factory-config.yaml\"))"
  type        = any
}

variable "manage_account_settings" {
  description = "Manage the account-wide settings (S3 account public access block, IAM password policy). Set true in one region only."
  type        = bool
  default     = false
}

locals {
  s3_bpa          = lookup(var.config, "enable_account_s3_block_public_access", null)
  password_policy = try(var.config["account_password_policy"]["update_account_password_policy"], false) ? var.config["account_password_policy"]["password_policy"] : null
  imds            = lookup(var.config, "require_imdsv2", null)
}

#
# Account-wide
#
resource "aws_s3_account_public_access_block" "payer" {
  count                   = var.manage_account_settings && local.s3_bpa != null ? 1 : 0
  block_public_acls       = local.s3_bpa["BlockPublicAcls"]
  ignore_public_acls      = local.s3_bpa["IgnorePublicAcls"]
  block_public_policy     = local.s3_bpa["BlockPublicPolicy"]
  restrict_public_buckets = local.s3_bpa["RestrictPublicBuckets"]
}

resource "aws_iam_account_password_policy" "payer" {
  count                          = var.manage_account_settings && local.password_policy != null ? 1 : 0
  minimum_password_length        = local.password_policy["MinimumPasswordLength"]
  require_symbols                = local.password_policy["RequireSymbols"]
  require_numbers                = local.password_policy["RequireNumbers"]
  require_uppercase_characters   = local.password_policy["RequireUppercaseCharacters"]
  require_lowercase_characters   = local.password_policy["RequireLowercaseCharacters"]
  allow_users_to_change_password = local.password_policy["AllowUsersToChangePassword"]
  max_password_age               = local.password_policy["MaxPasswordAge"]
  password_reuse_prevention      = local.password_policy["PasswordReusePrevention"]
  hard_expiry                    = local.password_policy["HardExpiry"]
}

#
# Regional
#
resource "aws_ebs_encryption_by_default" "payer" {
  count   = lookup(var.config, "enable_ebs_default_encryption", false) == true ? 1 : 0
  enabled = true
}

resource "aws_ebs_snapshot_block_public_access" "payer" {
  count = lookup(var.config, "enable_ebs_block_public_access", false) == true ? 1 : 0
  state = "block-all-sharing"
}

resource "aws_ec2_instance_metadata_defaults" "payer" {
  count                       = local.imds != null ? 1 : 0
  http_tokens                 = lookup(local.imds, "HttpTokens", "no-preference")
  http_put_response_hop_limit = lookup(local.imds, "HttpPutResponseHopLimit", 1)
  http_endpoint               = lookup(local.imds, "HttpEndpoint", "no-preference")
  instance_metadata_tags      = lookup(local.imds, "InstanceMetadataTags", "no-preference")
}

data "aws_vpcs" "default" {
  count = try(var.config["default_vpc"]["delete_default_vpc"], false) ? 1 : 0
  filter {
    name   = "is-default"
    values = ["true"]
  }
}

# Adopts the default VPC's default security group and removes all its rules (Security Hub EC2.2).
resource "aws_default_security_group" "payer" {
  count  = length(try(data.aws_vpcs.default[0].ids, []))
  vpc_id = data.aws_vpcs.default[0].ids[count.index]
}
