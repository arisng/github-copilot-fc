---
name: share
description: 'Share a visual explainer HTML file instantly via Vercel. Returns a live URL with no authentication required.'
---

# Share

# Share Visual Explainer Page

Share a visual explainer HTML file instantly via Vercel. Returns a live URL with no authentication required.

## Usage

```
/share <file-path>
```

**Arguments:**
- `file-path` - Path to the HTML file to share (required)

**Examples:**
```
/share ~/.agent/diagrams/my-diagram.html
/share /tmp/visual-explainer-output.html
```

## How It Works

1. Copies your HTML file to a temp directory as `index.html`
2. Deploys via the deploy-to-vercel skill (no auth needed)
3. Returns a live URL immediately
4. Returns a claim URL for optional ownership transfer

## Ad-hoc Shipping Model

This command is for **ad-hoc shipping**: publishing a single HTML artifact quickly for review and collaboration.

- It is optimized for speed and low friction, not long-term hosting guarantees.
- URLs are public-by-link and suitable for temporary sharing.
- Use the claim URL if you later want ownership under a Vercel account.

Use this for previews, reviews, and stakeholder walkthroughs. Use formal deployment workflows for persistent production endpoints.

## Requirements

- **Bash-capable shell** with standard utilities: `mktemp`, `cp`, `grep`, `head`
- **visual-explainer skill installed/published** so `{{skill_dir}}/scripts/share.sh` is available
- **If running from this repository first time**, publish the skill once:
  ```bash
  pwsh -NoProfile -File scripts/publish/publish-skills.ps1 -Skills "visual-explainer"
  ```
- **deploy-to-vercel skill** - Should be pre-installed. If not: `npx skills add https://github.com/vercel-labs/agent-skills --skill deploy-to-vercel`
- **Network access** to Vercel
- **Existing local HTML file** to publish

No Vercel account, Cloudflare account, or API keys needed. The deployment is "claimable" — you can transfer it to your Vercel account later if you want.

## First-Time Setup Checklist

Run once before first use:

```bash
# Script is available
test -f "{{skill_dir}}/scripts/share.sh" && echo "visual-explainer: OK"

# deploy-to-vercel bridge exists
test -f ~/.copilot/skills/deploy-to-vercel/resources/deploy.sh || test -f /mnt/skills/user/deploy-to-vercel/resources/deploy.sh || test -f ~/.pi/agent/skills/vercel-deploy/scripts/deploy.sh || test -f /mnt/skills/user/vercel-deploy/scripts/deploy.sh

# Smoke test deployment
printf '<!doctype html><html><body>hello</body></html>' > /tmp/ve-smoke.html
bash {{skill_dir}}/scripts/share.sh /tmp/ve-smoke.html
```

Expected result: command succeeds and prints both `Live URL` and `Claim URL`.

## Script Location

```bash
bash {{skill_dir}}/scripts/share.sh <file>
```

## Output

```
Sharing my-diagram.html...

✓ Shared successfully!

Live URL:  https://skill-deploy-abc123.vercel.app
Claim URL: https://vercel.com/claim-deployment?code=...
```

The script also outputs JSON for programmatic use:
```json
{"previewUrl":"https://...","claimUrl":"https://...","deploymentId":"...","projectId":"..."}
```

## Notes

- Deployments are **public** — anyone with the URL can view
- Preview deployments have a configurable retention period (default: 30 days)
- Each share creates a new deployment with a unique URL

## Context

$ARGUMENTS
