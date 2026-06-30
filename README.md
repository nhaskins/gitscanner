# gitscan

A containerized workspace for auditing Git repositories before making them public. Clone candidate repos into `repos/`, run automated secret scans, review reports, and manually verify before publishing.

Built on **Debian Bookworm** (not the Microsoft devcontainer base image) with [Gitleaks](https://github.com/gitleaks/gitleaks) and [TruffleHog](https://github.com/trufflesecurity/trufflehog).

## Project layout

```
.
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile
├── scripts/
│   ├── scan-repo.sh    # Scan one repository
│   └── scan-all.sh     # Scan every folder in repos/
├── repos/              # Clone candidate repos here
├── reports/            # JSON/text scan output (gitignored)
└── README.md
```

## Quick start (Dev Container)

1. Open this folder in Cursor or VS Code.
2. Run **Dev Containers: Reopen in Container** (or accept the prompt to reopen remotely).
3. Wait for the image to build. Scanner versions are pinned in `.devcontainer/Dockerfile` and can be overridden with build args.
4. Clone a repo to audit:

   ```bash
   git clone https://github.com/you/your-repo.git repos/your-repo
   ```

5. Scan it:

   ```bash
   ./scripts/scan-repo.sh repos/your-repo
   ```

6. Review output in `reports/your-repo/`.

## Scanning

### Scan one repository

```bash
./scripts/scan-repo.sh repos/<name>
```

This runs:

- **Gitleaks** — full git history scan (`gitleaks detect`)
- **TruffleHog** — full git history via local path (`trufflehog git file://...`)

Reports are written to `reports/<name>/`:

| File | Description |
|------|-------------|
| `gitleaks.json` | Gitleaks findings (JSON) |
| `gitleaks.log` | Gitleaks console output |
| `trufflehog.json` | TruffleHog findings (JSON) |
| `trufflehog.log` | TruffleHog stderr/log output |
| `scan-summary.txt` | Human-readable run summary |

### Scan all repositories

```bash
./scripts/scan-all.sh
```

Scans every direct child folder inside `repos/`. The batch continues even when one repo reports findings.

### Filesystem-only mode (current files, no git history)

Use this for a quick pass over the working tree only:

```bash
./scripts/scan-repo.sh --filesystem-only repos/<name>
./scripts/scan-all.sh --filesystem-only
```

- Gitleaks uses `--no-git`
- TruffleHog uses `filesystem` instead of `git`

Git history can still contain secrets removed from the current tree — always run the default git-history scan before publishing.

### TruffleHog `--only-verified`

Scans use `--only-verified` by default. TruffleHog only reports secrets it can actively verify as live. This reduces noise but may miss unverified patterns.

To scan with more (noisier) results, edit `scripts/scan-repo.sh` and remove `--only-verified` from the TruffleHog commands.

## Manual verification

Automated scanners are not enough. After scans, manually inspect:

- `.env`, `.env.*`, config files, and sample data
- Screenshots and exported credentials
- Git commit history (`git log -p`, `git log --all --full-history -- <file>`)
- Build artifacts, CI config, and cloud provider keys

### ripgrep examples

From inside a repo directory:

```bash
cd repos/your-repo

# Broad keyword search (case-insensitive, with line numbers)
rg -n -i "api[_-]?key|secret|token|password|private[_-]?key|client_secret|BEGIN .*PRIVATE" .

# Common env-style assignments
rg -n -i "(aws_|github_|gitlab_|slack_|stripe_|openai_).*(key|token|secret)" .

# PEM private keys
rg -n "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY"
```

### grep fallback

```bash
grep -RInE "api[_-]?key|secret|token|password|private[_-]?key" .
```

## If secrets are found

**Removing a secret from Git history is not enough.** Anyone who ever had access to the repo, a fork, a backup, or a cached clone may still have it.

Correct order of operations:

1. **Revoke and rotate** the exposed credential immediately (API key, token, password, certificate, etc.).
2. Confirm the old credential no longer works.
3. Clean the repository and rewrite history if needed (`git filter-repo`, BFG, etc.).
4. Re-run `./scripts/scan-repo.sh` and manual checks.
5. Only then consider the repo safe to publish.

Treat every reported secret as compromised until rotated.

## Checklist before making a repo public

1. Clone the repo into `repos/`
2. Run `./scripts/scan-repo.sh repos/<name>`
3. Review everything in `reports/<name>/`
4. Manually inspect `.env`, config files, screenshots, sample data, and full commit history
5. **Rotate any secret found**, even if it was removed from history
6. Remove private client data, internal URLs, and personal information
7. Re-run scans until clean
8. Only then make the repository public

## Installed tools

| Tool | Version (default) | Purpose |
|------|-------------------|---------|
| Gitleaks | 8.30.1 | Pattern-based secret detection in git repos |
| TruffleHog | 3.95.6 | Verified secret detection across git history |
| git, curl, wget, jq, ripgrep, openssh-client, … | apt | Cloning and manual inspection |

Versions are set via `ARG` in `.devcontainer/Dockerfile` and mirrored in `devcontainer.json` build args. Override at build time:

```bash
docker build \
  --build-arg GITLEAKS_VERSION=8.30.1 \
  --build-arg TRUFFLEHOG_VERSION=3.95.6 \
  -f .devcontainer/Dockerfile \
  -t gitscan .
```

## Private repositories

To clone private repos inside the dev container, mount your SSH keys by adding to `.devcontainer/devcontainer.json`:

```json
"mounts": [
  "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
]
```

Do not commit keys or tokens into this workspace.

## What is not committed

- `repos/*` — cloned repositories (may contain secrets)
- `reports/*` — scan output (may describe findings in detail)

Both directories keep a `.gitkeep` so the folder structure is preserved in git.
