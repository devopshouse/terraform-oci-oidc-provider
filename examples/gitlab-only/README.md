# Example: GitLab CI OIDC (GitLab SaaS)

Sets up OIDC workload identity federation for GitLab CI using `https://gitlab.com`. Secrets are not written automatically — retrieve them from Terraform outputs and store them as GitLab CI/CD variables (masked).

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

After apply, store the outputs as **masked** CI/CD variables in GitLab (Settings → CI/CD → Variables):

```bash
terraform output -raw ci_oidc_config_json   # → OCI_OIDC_CONFIG variable (OCI + OCIR fields unified)
```

Also note the audience value for your pipeline:

```bash
terraform output gitlab_oidc_audience   # → use in id_tokens.OCI_TOKEN.aud
```

## What gets created

- IDCS service user `svc-ci` for UPST impersonation
- Dedicated OCIR user `svc-ci-ocir`, auth token, group, and policy
- IDCS group `grp-ci-actions` containing only the UPST service user
- IDCS Confidential Application and Identity Propagation Trust for GitLab CI
- IAM policy granting the CI group access to the configured compartment

## Pipeline authentication

Copy [`gitlab-ci.yml`](gitlab-ci.yml) to `.gitlab-ci.yml` in your repository. It shows how to:

1. Use the `id_tokens` block to request a GitLab OIDC JWT
2. Exchange the JWT for an OCI UPST
3. Log in to OCIR for Docker operations
