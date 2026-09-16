# GitHub Secrets Configuration Guide

## Overview

This guide explains how to configure GitHub Repository Secrets required for the AshipaOS CI/CD pipeline. These secrets enable secure artefact signing, cloud storage, and hardware lab access.

## Required Secrets

### 1. GPG_PRIVATE_KEY (Required)

**Purpose:** Signs release artefacts in Layer 10 (Release Engineering) to ensure integrity and authenticity.

**How to Generate:**
```bash
./scripts/setup-github-secrets.sh
```
Or manually:
```bash
gpg --batch --gen-key <<EOF
%echo Generating AshipaOS Release Key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: AshipaOS Release Bot
Name-Email: release@ashipaos.local
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF

gpg --armor --export-secret-keys release@ashipaos.local
```

**Configuration Steps:**
1. Copy the entire output including `-----BEGIN PGP PRIVATE KEY BLOCK-----` and `-----END PGP PRIVATE KEY BLOCK-----`
2. Go to GitHub Repository → Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `GPG_PRIVATE_KEY`
5. Value: Paste the full armored key
6. Click "Add secret"

### 2. GPG_PASSPHRASE (Optional but Recommended)

**Purpose:** Unlocks the GPG private key during the signing process.

**Note:** If you generated the key with `%no-protection` (as in our script), this secret can be left empty or set to any value.

**Configuration Steps:**
1. Generate a secure passphrase: `openssl rand -base64 32`
2. Go to GitHub Repository → Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `GPG_PASSPHRASE`
5. Value: Your secure passphrase
6. Click "Add secret"

### 3. AWS_ACCESS_KEY_ID (Optional)

**Purpose:** Uploads release artefacts to Amazon S3 for distribution.

**Prerequisites:**
- AWS Account with IAM permissions
- S3 bucket created for artefacts

**IAM Policy Required:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectAcl"
      ],
      "Resource": "arn:aws:s3:::your-ashipaos-artefacts-bucket/*"
    }
  ]
}
```

**Configuration Steps:**
1. Go to AWS IAM Console → Users → Create User
2. Attach the policy above (replace bucket name)
3. Create access keys for the user
4. Copy the Access Key ID
5. Go to GitHub Repository → Settings → Secrets and variables → Actions
6. Click "New repository secret"
7. Name: `AWS_ACCESS_KEY_ID`
8. Value: Paste the access key ID (e.g., `AKIAIOSFODNN7EXAMPLE`)
9. Click "Add secret"

### 4. AWS_SECRET_ACCESS_KEY (Optional)

**Purpose:** Paired with AWS_ACCESS_KEY_ID for S3 authentication.

**Configuration Steps:**
1. Use the Secret Access Key from the IAM user created above
2. Go to GitHub Repository → Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `AWS_SECRET_ACCESS_KEY`
5. Value: Paste the secret access key (e.g., `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
6. Click "Add secret"

⚠️ **Security Warning:** Never commit AWS credentials to your repository. Always use GitHub Secrets.

### 5. HARDWARE_LAB_TOKEN (Optional)

**Purpose:** Authenticates with the hardware lab API for physical device testing (HARDWARE verification class).

**Generation:**
```bash
openssl rand -hex 32
```

**Configuration Steps:**
1. Generate token: `openssl rand -hex 32`
2. Go to GitHub Repository → Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `HARDWARE_LAB_TOKEN`
5. Value: Paste the generated token
6. Click "Add secret"

**Hardware Lab Server Configuration:**
On your hardware lab server, configure the same token:
```bash
echo "HARDWARE_LAB_TOKEN=your_generated_token_here" >> /etc/hardware-lab/config.env
```

## Verification

After configuring all secrets, verify the setup:

### 1. Test GPG Signing
```bash
gh workflow run build-images.yml --ref main
```
Check the workflow logs for "Signing artefacts..." step success.

### 2. Test S3 Upload (if configured)
Monitor the "Upload to S3" step in the build-images workflow.

### 3. Test Hardware Lab Connection
```bash
gh workflow run hardware-lab.yml --ref main
```
Check for successful authentication with the hardware lab API.

## Security Best Practices

1. **Rotate Keys Regularly:** Regenerate GPG keys and AWS credentials every 90 days.
2. **Use OIDC Where Possible:** For AWS, consider using GitHub's OIDC provider instead of long-lived credentials.
3. **Limit Secret Scope:** Only grant secrets to specific workflows if possible using environment protection rules.
4. **Audit Access:** Regularly review who has access to repository settings and secrets.
5. **Use Environment Protection Rules:** Configure production environments with required reviewers for release workflows.

## Troubleshooting

### GPG Signing Fails
- Ensure the private key includes both BEGIN and END markers
- Check that the key is not corrupted (no extra newlines or spaces)
- Verify the key has subkeys for signing

### AWS Upload Fails
- Verify IAM policy permissions are correct
- Check that the S3 bucket exists and is accessible
- Ensure the bucket region matches your configuration

### Hardware Lab Tests Skip
- Verify the token matches on both GitHub and the lab server
- Check that self-hosted runners are online and registered
- Review hardware lab server logs for authentication errors

## Next Steps

After configuring secrets:
1. Enable GitHub Pages for publishing release notes
2. Configure environment protection rules for production releases
3. Set up branch protection rules requiring CI checks to pass
4. Register self-hosted runners for hardware lab machines

---

**Generated by:** `scripts/setup-github-secrets.sh`
**Last Updated:** $(date -Iseconds)
