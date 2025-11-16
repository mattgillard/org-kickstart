# Additional Permission Sets

This repository now supports adding additional permission sets beyond the default AdministratorAccess permission set, using a flexible map-based configuration.

## Architecture

- **Admin permission set**: Remains unchanged and is always available
- **Additional permission sets**: Defined via the `additional_permission_sets` variable
- **Automatic propagation**: Additional permission sets are automatically assigned to ALL accounts (existing and new)

## Usage

### Adding a Read-Only Permission Set

To add a read-only permission set, add the following to your `.tfvars` file:

```hcl
additional_permission_sets = {
  "ReadOnlyAccess" = {
    description        = "Read-only access to AWS resources"
    managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    group_name         = "ReadOnlyUsers"
  }
}
```

This will:
1. Create a permission set named "ReadOnlyAccess"
2. Attach the AWS managed `ReadOnlyAccess` policy to it
3. Create an Identity Center group named "ReadOnlyUsers"
4. Assign the permission set to the group across all accounts in the organization

### Adding Multiple Permission Sets

You can add multiple permission sets at once:

```hcl
additional_permission_sets = {
  "ReadOnlyAccess" = {
    description        = "Read-only access to AWS resources"
    managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    group_name         = "ReadOnlyUsers"
  }
  "PowerUserAccess" = {
    description        = "Power user access without IAM permissions"
    managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
    group_name         = "PowerUsers"
    session_duration   = "PT12H"  # Optional: Override default session duration
  }
  "SecurityAuditAccess" = {
    description        = "Security audit access"
    managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
    group_name         = "SecurityAuditors"
  }
}
```

## Configuration Options

### Required Fields

- `description`: Description of the permission set
- `managed_policy_arn`: ARN of the AWS managed policy to attach
- `group_name`: Name of the Identity Center group to create

### Optional Fields

- `session_duration`: Override the default session duration (e.g., "PT12H" for 12 hours)
  - If not specified, uses the global `session_duration` variable
  - Format: ISO 8601 duration format (PT#H for hours)

## Common AWS Managed Policies

Here are some commonly used AWS managed policies:

- `arn:aws:iam::aws:policy/ReadOnlyAccess` - Read-only access to all AWS services
- `arn:aws:iam::aws:policy/PowerUserAccess` - Full access except IAM and Organizations
- `arn:aws:iam::aws:policy/ViewOnlyAccess` - More restrictive read-only access
- `arn:aws:iam::aws:policy/SecurityAudit` - Security-focused read access
- `arn:aws:iam::aws:policy/job-function/DatabaseAdministrator` - Database admin access
- `arn:aws:iam::aws:policy/job-function/NetworkAdministrator` - Network admin access

For a complete list, see: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_job-functions.html

## Disabling SSO Management

If you have `disable_sso_management = true`, additional permission sets will not be created (similar to how the admin permission set behaves).

## Account Assignment

Additional permission sets are automatically assigned to:
- All accounts created via the `accounts` variable
- The security account
- The payer (management) account

This ensures consistent access across your entire AWS Organization.

## Adding Users to Groups

After applying this configuration:

1. Log in to the AWS Identity Center console
2. Navigate to "Groups"
3. Find the group you created (e.g., "ReadOnlyUsers")
4. Add users to the group

Users will then be able to access all accounts in the organization with the assigned permission set.

