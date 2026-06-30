# Example: GitHub Actions OIDC (GitHub Only)

Sets up OIDC workload identity federation for two GitHub repositories. After `terraform apply`, `OCI_OIDC_CONFIG` is written as an encrypted GitHub Actions secret in each repository. No long-lived OCI credentials are stored.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

## What gets created

- IDCS service user `svc-ci` for UPST impersonation
- Dedicated OCIR user `svc-ci-ocir`, auth token, group, and policy
- IDCS group `grp-ci-actions` containing only the UPST service user
- IDCS Confidential Application and Identity Propagation Trust for GitHub Actions
- IAM policy granting the CI group access to the configured compartment
- GitHub Actions secret `OCI_OIDC_CONFIG` in each listed repository (OCI + OCIR fields unified)

## Workflow authentication

Copy [`workflow.yml`](workflow.yml) to `.github/workflows/oci-auth.yml` in your repository. It shows how to:

1. Request the GitHub OIDC JWT and exchange it for an OCI UPST
2. Log in to OCIR for Docker push/pull operations
3. Use the UPST with the OCI CLI or SDK
