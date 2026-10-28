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

# Organization-wide IAM Access Analyzer (external access) in one region.
#
# Call once per region with a security-account provider for that region, after the root
# module has delegated Access Analyzer administration (enable_access_analyzer = true), e.g.
# depends_on = [module.organization]. The analyzer covers every account in the
# organization, including the management account. External-access analyzers are free;
# unused-access analyzers are billed per IAM role and user and are not created here.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0"
    }
  }
}

variable "analyzer_name" {
  description = "Name of the organization external-access analyzer."
  type        = string
  default     = "org-external-access"
}

resource "aws_accessanalyzer_analyzer" "organization" {
  analyzer_name = var.analyzer_name
  type          = "ORGANIZATION"
}

output "analyzer_arn" {
  value = aws_accessanalyzer_analyzer.organization.arn
}
