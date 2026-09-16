# CI/CD Pipeline Activation Checklist

## ✅ Completed Steps

### 1. GitHub Secrets Generated
- [x] GPG key pair generated (`output/gpg_private_key.asc`)
- [x] GPG passphrase generated (`output/gpg_passphrase.txt`)
- [x] Hardware lab token generated
- [x] AWS credentials template prepared

**Secrets Ready for Configuration:**
| Secret Name | Status | Location |
|-------------|--------|----------|
| `GPG_PRIVATE_KEY` | ✅ Generated | `output/gpg_private_key.asc` |
| `GPG_PASSPHRASE` | ✅ Generated | `output/gpg_passphrase.txt` |
| `AWS_ACCESS_KEY_ID` | ⏭️ Manual | Create in AWS IAM Console |
| `AWS_SECRET_ACCESS_KEY` | ⏭️ Manual | Create in AWS IAM Console |
| `HARDWARE_LAB_TOKEN` | ✅ Generated | See below |

### 2. GitHub Actions Workflows Updated
- [x] `pr.yml` - Enhanced with full build pipeline
  - Installs dependencies (debootstrap, qemu-user-static, etc.)
  - Runs static tests for all layers
  - Smoke tests Layer 1 (rootfs) and Layer 2 (image)
  - Uploads evidence artefacts
  
- [x] `build-images.yml` - Complete release pipeline
  - Triggers on tags (`v*.*.*`) or manual dispatch
  - Matrix builds for x86_64 and a95x-f3-air
  - Full layer build chain (1-10)
  - GPG signing integration
  - SBOM generation
  - GitHub Release creation

### 3. CI Helper Scripts Created
- [x] `scripts/ci-sign-artefacts.sh` - GPG signing script
- [x] `scripts/ci-generate-sbom.sh` - SBOM generation script
- [x] `scripts/setup-github-secrets.sh` - Secret generation script

### 4. Documentation Updated
- [x] `docs/GITHUB_SECRETS_SETUP.md` - Comprehensive setup guide

---

## ⏭️ Next Steps (Manual Actions Required)

### Step 1: Configure GitHub Secrets (5 minutes)
1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** for each:

   ```
   Name: GPG_PRIVATE_KEY
   Value: [Copy entire contents of output/gpg_private_key.asc]
   
   Name: GPG_PASSPHRASE
   Value: 4MTR0awx0pXW9fD+vAr+fWbV6lnwj8Q9v+AFpT2xWwQ=
   
   Name: HARDWARE_LAB_TOKEN (optional)
   Value: ff67af723e3b572a68080446e35baa4fb9d7f433d953898857f4a7d15933baef
   ```

### Step 2: Enable GitHub Actions (1 minute)
1. Go to **Settings** → **Actions** → **General**
2. Select **Allow all actions and reusable workflows**
3. Click **Save**

### Step 3: Push Code to Repository (1 minute)
```bash
git add .
git commit -m "feat: complete Layers 0-10 implementation with CI/CD"
git push origin main
```

### Step 4: Verify PR Workflow (automatic)
- The `pr.yml` workflow will automatically trigger on push
- Monitor at: **Actions** tab → **pr** workflow
- Expected duration: ~15-20 minutes
- Should show: ✅ All static tests pass, ✅ Smoke builds succeed

### Step 5: Create First Release Tag (optional)
```bash
git tag v0.1.0-alpha
git push origin v0.1.0-alpha
```
- This triggers the full `build-images.yml` workflow
- Creates GitHub Release with signed artefacts
- Expected duration: ~45-60 minutes for both targets

---

## 📋 Verification Commands

After pushing, verify workflows are running:
```bash
# List recent workflow runs
gh run list --limit 5

# Watch a specific run
gh run watch <RUN_ID>

# View logs
gh run view <RUN_ID> --log
```

Or via GitHub UI:
- **Actions** tab shows all workflow runs
- Green checkmark = success
- Red X = failure (click to see logs)

---

## 🎯 Expected Outcomes

### After Step 4 (PR Workflow):
- ✅ Static tests pass for all 10 layers
- ✅ Layer 1 rootfs builds successfully (x86_64)
- ✅ Layer 2 disk image creates successfully (x86_64)
- ✅ Evidence artefacts uploaded

### After Step 5 (Release Build):
- ✅ Full build pipeline completes for x86_64
- ✅ Full build pipeline completes for a95x-f3-air
- ✅ Artefacts signed with GPG
- ✅ SBOM generated
- ✅ GitHub Release created with:
  - `ashipaos-x86_64-v0.1.0-alpha.img.gz`
  - `ashipaos-a95x-f3-air-v0.1.0-alpha.img.gz`
  - `*.pkg` OTA packages
  - `sbom.json`
  - Detached `.sig` signatures

---

## 🚨 Troubleshooting

### Workflow doesn't start after push
- Check **Settings** → **Actions** → **General** → Ensure actions are enabled
- Verify `.github/workflows/` directory exists with valid YAML files

### GPG signing fails
- Ensure `GPG_PRIVATE_KEY` includes BEGIN/END markers
- Check `GPG_PASSPHRASE` matches the generated value
- Verify no extra whitespace in secret values

### Build fails on Layer 1
- Check workflow logs for debootstrap errors
- Ensure Ubuntu runner has sufficient disk space (minimum 10GB free)
- Verify network connectivity for downloading Debian packages

---

## 📞 Support

If you encounter issues:
1. Check workflow logs in GitHub Actions tab
2. Review `docs/GITHUB_SECRETS_SETUP.md` for detailed configuration
3. Run local smoke test: `./layers/layer1-rootfs/build-rootfs.sh build x86_64`
4. Verify static tests locally: `./layers/layer1-rootfs/tests/static-tests.sh`

---

**Status**: Ready for activation ✅  
**Estimated Setup Time**: 10 minutes  
**Next Action**: Configure GitHub Secrets in repository settings
