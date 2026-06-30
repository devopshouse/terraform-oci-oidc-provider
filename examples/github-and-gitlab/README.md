# Example: GitHub Actions + GitLab CI (Both Platforms)

Federates both GitHub Actions and GitLab CI simultaneously. Both platforms share the same IDCS service user and Confidential Application, while OCIR uses a dedicated user, group, auth token, and policy. Two separate Identity Propagation Trusts are created, one per platform.

GitHub secrets are written automatically. GitLab secrets must be stored manually from Terraform outputs.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

Store GitLab CI/CD variables (masked) after apply:

```bash
terraform output -raw ci_oidc_config_json   # → OCI_OIDC_CONFIG variable in GitLab (OCI + OCIR fields unified)
terraform output gitlab_oidc_audience       # → use in id_tokens.OCI_TOKEN.aud
```

## CI pipeline snippets

- **GitHub Actions:** copy [`workflow.yml`](workflow.yml) to `.github/workflows/oci-auth.yml`
- **GitLab CI:** copy [`gitlab-ci.yml`](gitlab-ci.yml) to `.gitlab-ci.yml`
