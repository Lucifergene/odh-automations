# Contributing to odh-automations

## Adding a new sentinel

1. Create `sentinels/<name>/` with `scripts/` and `tests/`.
2. Add `sentinels/<name>/OWNERS` with approvers for that area.
3. Add background docs in `docs/<name>-sentinel.md` if the sentinel needs incident history or architecture context beyond the root README.
3. Add `.github/workflows/<name>-sentinel-nightly.yml` with:
   - `schedule` (cron) — stagger from existing sentinels to avoid resource contention
   - `workflow_dispatch` for manual runs
   - No `push` or `pull_request` triggers on expensive Kind/E2E jobs unless explicitly required
4. Reuse `sentinels/shared/scripts/` where possible.
5. Add a row to the sentinel table in [README.md](README.md).
6. Register an alias in [OWNERS_ALIASES](OWNERS_ALIASES) if the sentinel has a dedicated review group.

## Testing locally

```bash
pip install -r requirements-dev.txt
make test
```

Kueue notify script combinations:

```bash
make test-kueue
```

## Workflow conventions

- Workflow file name: `<name>-sentinel-nightly.yml`
- Workflow display name: `<Name> Sentinel - Daily Compatibility Check`
- Script paths: `./sentinels/<name>/scripts/...`
- Shared utilities: `./sentinels/shared/scripts/...`

## Pull requests

Use the PR template. Include:

- Which sentinel(s) changed
- How you tested (local `make test`, manual workflow run, or both)
- Any new secrets or Slack webhook variables required

## Code of conduct

This project follows the [Open Data Hub code of conduct](https://github.com/opendatahub-io/opendatahub-io/blob/main/CODE_OF_CONDUCT.md).
