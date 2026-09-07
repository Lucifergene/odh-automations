# odh-automations

Nightly compatibility sentinels for [Open Data Hub Dashboard](https://github.com/opendatahub-io/odh-dashboard) upstream dependencies.

Each sentinel lives under `sentinels/<name>/` and runs on a schedule via GitHub Actions. Failures post to Slack before they reach production clusters.

## Sentinels

| Sentinel | Upstream | Schedule (UTC) | Workflow | Background |
|----------|----------|----------------|----------|------------|
| OGX | OGX / Gen AI BFF | 06:30 | [ogx-sentinel-nightly.yml](.github/workflows/ogx-sentinel-nightly.yml) | — |
| Kueue | Kueue + Kubeflow Trainer | 07:30 | [kueue-sentinel-nightly.yml](.github/workflows/kueue-sentinel-nightly.yml) | [docs/kueue-sentinel.md](docs/kueue-sentinel.md) |

Workflows trigger on **schedule** and **manual dispatch** only. Pushing to this repo does not start a sentinel run.

### OGX sentinel

Tests `odh-dashboard/packages/gen-ai/bff` against latest OGX releases from PyPI (stable) and test.pypi.org (dev). Replay mode first; recording mode if fixtures are missing.

| Secret | Purpose |
|--------|---------|
| `SLACK_WEBHOOK_URL` | Slack Workflow Builder webhook |
| `GFEMINI_API_KEY` | Recording mode when replay fixtures are missing |

### Kueue sentinel — three layers

```
Layer 1 (Contract)  →  Layer 2 (Dry-run)  →  Layer 3 (Integration)  →  Slack
     every PR              nightly Kind           same cluster
```

| Layer | When | What it catches |
|-------|------|-----------------|
| L1 Contract | Every PR in odh-dashboard, ~30s | TypeScript types vs pinned CRD fixtures |
| L2 Dry-run | Nightly, ~10m | API server / webhook rejects dashboard manifests |
| L3 Integration | Nightly, ~5m | Full TrainJob lifecycle on Kind |

Incident history, Slack context, and layer mapping: [docs/kueue-sentinel.md](docs/kueue-sentinel.md).

| Secret | Purpose |
|--------|---------|
| `KUEUE_SENTINEL_SLACK_WEBHOOK_URL` | Slack Workflow Builder webhook |

## Repository layout

```
.github/workflows/     # One workflow per sentinel
docs/                  # Sentinel background docs (Markdown)
sentinels/
  <name>/
    scripts/           # CI helper scripts
    tests/             # Script tests
    OWNERS             # Per-sentinel review ownership (Prow)
  shared/
    scripts/           # Utilities shared across sentinels
    tests/
```

## Development

```bash
pip install -r requirements-dev.txt
make test          # all tests
make test-kueue    # Kueue notify script tests
make lint          # workflow YAML lint
```

Manual workflow runs: **Actions** → pick a sentinel workflow → **Run workflow**.

## Adding a new sentinel

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [new sentinel issue template](.github/ISSUE_TEMPLATE/new_sentinel.yml).

## License

Apache License 2.0. See [LICENSE](LICENSE).
