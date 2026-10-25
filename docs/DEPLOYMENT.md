# Deployment Guide (Windows / PowerShell)

Total time: about 1 hour of work plus roughly 20 minutes of waiting for the first deployment.

## 0. Install tools (once)

```powershell
winget install Amazon.AWSCLI
winget install Hashicorp.Terraform
winget install Git.Git
winget install GitHub.cli     # optional
```
Close and reopen PowerShell. Check: `aws --version`, `terraform -version`, `git --version`.

## 1. Basic AWS configuration

1. Sign in to the AWS console as root and turn on MFA.
2. IAM → Users → Create user (for example `admin-cli`) → attach `AdministratorAccess`.
3. Open the user → Security credentials → Create access key → "Command Line Interface".
4. In PowerShell:
   ```powershell
   aws configure
   # Access key ID, secret, region: ap-south-1, output: json
   aws sts get-caller-identity
   ```
   The last command should print your account ID.
5. Set a budget alert: Billing → Budgets → Create budget → monthly cost budget of about 20 USD with an email alert.

## 2. Domain and Route53 hosted zone

The HTTPS certificate needs a domain you control.

- **No domain:** Route53 → Registered domains → Register (a `.click` domain costs a few dollars). This creates the hosted zone for you.
- **Domain bought elsewhere:** Route53 → Hosted zones → Create (public), then copy its 4 nameservers into your registrar's DNS settings.

Check: `aws route53 list-hosted-zones`. Note the zone name, for example `example.com`. The dev environment will live at `dev.example.com` (prod uses `app.example.com`).

## 3. Create the GitHub repository

Create an empty repo on GitHub (for example `devops-task`). Do not push yet.

## 4. Bootstrap AWS (once, from your laptop)

This creates the Terraform state bucket, the releases bucket, the GitHub OIDC provider and the IAM role GitHub will use.

```powershell
cd bootstrap
terraform init
terraform apply -var="github_repo=YOURUSER/devops-task"
```
Type `yes`. Copy the four outputs.

If it says the OIDC provider already exists, run again with `-var="create_oidc_provider=false"`.

## 5. Configure GitHub

Repo → Settings → Secrets and variables → Actions.

**Secret:** `AWS_ROLE_ARN` = output `AWS_ROLE_ARN`

**Variables:**

| Name | Value |
|---|---|
| `AWS_REGION` | `ap-south-1` |
| `TF_STATE_BUCKET` | output `TF_STATE_BUCKET` |
| `RELEASES_BUCKET` | output `RELEASES_BUCKET` |
| `DOMAIN_NAME` | your hosted zone, for example `example.com` |

Optional: Settings → Environments → `prod` → add yourself as a required reviewer to get a manual approval step before production deploys. GitHub creates the `dev` and `prod` environments the first time they are used.

## 6. Push and deploy

From the repo root:

```powershell
cd ..
git init
git add .
git commit -m "Infrastructure, app and blue/green pipeline"
git branch -M main
git remote add origin https://github.com/YOURUSER/devops-task.git
git push -u origin main
```

Open the **Actions** tab. The *Deploy (Blue/Green)* run validates, uploads the release and creates everything. The first run takes about 15 to 25 minutes (RDS and certificate validation are the slow parts). If you pushed before setting the variables, fix them and use Actions → Run workflow → `deploy`.

## 7. Verify

```powershell
curl.exe -I http://dev.example.com             # 301 redirect to HTTPS
curl.exe https://dev.example.com/health        # {"status":"ok"...}
curl.exe https://dev.example.com/health/db     # {"status":"ok","db":"connected"}
curl.exe https://dev.example.com/version       # release and colour (blue on first deploy)
curl.exe https://dev.example.com/db/status     # writer read_only=0, reader read_only=1 (the replica)
curl.exe -X POST https://dev.example.com/api/notes -H "content-type: application/json" -d "{\"text\":\"hello\"}"
curl.exe https://dev.example.com/api/notes
```
Open the URL in a browser and confirm the padlock.

## 8. Demonstrate blue/green

1. Edit `app/server.js` (for example change the `<h1>` text) and push to `main`.
2. Watch the workflow log: it deploys to **green**, waits for healthy targets, switches traffic, runs the smoke test.
3. Refresh the page: the colour badge changes from BLUE to GREEN and the release id changes. `curl.exe https://dev.example.com/version` shows the same.
4. Push again and it flips back to blue.

## 9. Roll back

Actions → *Deploy (Blue/Green)* → Run workflow → action `rollback`. Traffic returns to the previous colour, which was kept warm.

## 10. Screenshots to take

1. GitHub Actions run, green, with the blue/green log steps
2. VPC resource map (VPC → your VPC → Resource map)
3. ALB listeners (443 forward with weights, 80 redirect)
4. Both target groups, one healthy and one idle or draining
5. Auto Scaling groups (blue and green) with instances in 2 AZs
6. RDS: primary and read replica (Replication role shown), Publicly accessible = No, encryption enabled
6b. `/db/status` output showing the writer and the read-only reader
7. Secrets Manager secret
8. S3 buckets, and ALB log files in the logs bucket
9. Browser with the padlock showing the BLUE page, then the GREEN page after a deploy
10. Terminal showing the `curl` checks

## 11. Free tier and cost

- A read replica is a second RDS instance, so it uses the shared 750 free hours twice as fast and is billed at the normal rate after that (about 0.016 USD per hour for a `db.t3.micro`).
- The NAT gateway and ALB are never free. Expect a few dollars per day while the stack is up.
- Plan: deploy, take screenshots, then destroy within a day or two. To avoid replica charges entirely, set `db_create_read_replica = false` in `terraform/envs/dev/terraform.tfvars` and push.
- Check Billing → Free tier in the console to see what your account actually includes.

## 12. Clean up

Run Actions → Run workflow → `destroy`, then remove the bootstrap resources:

```powershell
cd bootstrap
terraform destroy -var="github_repo=YOURUSER/devops-task"
```
The NAT gateway, ALB and RDS bill hourly, so do not leave them running.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Workflow fails at "Configure AWS credentials" | `AWS_ROLE_ARN` secret wrong, or `github_repo` in bootstrap does not match `owner/repo` exactly |
| `couldn't find resource` for the hosted zone | `DOMAIN_NAME` does not match the Route53 zone name |
| Certificate validation hangs | Registrar nameservers do not point to the Route53 zone yet |
| Terraform times out waiting for healthy instances | App failed to start. Use Systems Manager → Session Manager on an instance and run `journalctl -u app -n 50` and `tail -50 /var/log/cloud-init-output.log` |
| `terraform fmt -check` fails | Run `terraform fmt -recursive` locally, commit and push |
| `FreeTierRestrictionError` on RDS | A setting exceeds the free tier (for example backup retention above 1 day, Multi-AZ, or a larger instance class). Use the dev defaults |
| Replica creation takes long | Normal: it takes about 10 minutes after the primary; the first deploy is slower with a replica |
| `NoSuchKey` in instance logs | The release zip is missing from the releases bucket; re-run the deploy workflow |

## Interview talking points

- Why two target groups and weighted listener rules instead of swapping DNS: instant switch, instant rollback, no DNS caching.
- Why the release version is in the ASG name: a new release creates a new ASG and Terraform waits for health before removing the old one.
- Why DB subnets have no route out, and why security groups reference each other instead of CIDRs.
- Why OIDC instead of access keys.
- What you would change for production: scoped CI role, NAT per AZ, Multi-AZ RDS, WAF, CloudWatch alarms, RDS CA verification.
