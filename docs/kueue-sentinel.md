# Kueue Sentinel

Nightly compatibility check between ODH Dashboard and upstream Kueue + Kubeflow Trainer.

**Visual report (screenshots, formatted layout):** https://kueue-odh-sentinel.pages.dev/

## The problem

The ODH Dashboard calls Kubernetes APIs to manage Kueue and Kubeflow Trainer resources. The dashboard team does not control those upstream operators. When they change without warning, the dashboard breaks.

Until the sentinel existed, the team found out the same way every time: a nightly E2E test failed, someone filed a Jira, and the fix happened after the fact. Two Jira blockers confirmed the pattern:

- `RHOAIENG-58488` — Kueue API version change
- `RHOAIENG-88520` — Trainer immutability change

Both were discovered in production.

Engineers had been asking for proactive notification independently:

> "I think we should be notified/informed about any upcoming Kueue version upgrades so we could track these and keep an eye out for them."
> — Claudia Alphonse

> "I see this was done at very last moment… way after code freeze for 3.5 GA. Is there any channel which communicates this?"
> — Purva Naik

> "I have some concerns on how we will handle the fact RHBoK can be lifecycled independent of RHOAI — if RHBoK 2.0 suddenly becomes available, how is Dashboard intended to react on an unsupported API?"
> — Andy

## How it works

The pipeline runs every night at **07:30 UTC** (1 hour after the OGX sentinel). It fetches the latest Kueue and Trainer releases from GitHub, spins up a Kind cluster, and runs three layers of tests. Failures post to Slack before the team starts their day.

```
Layer 1 (Contract)  →  Layer 2 (Dry-run)  →  Layer 3 (Integration)  →  Slack
     every PR              nightly Kind           same cluster
```

| Layer | Name | When | What it catches |
|-------|------|------|-----------------|
| L1 | Contract Tests | Every PR, ~30s | TypeScript types vs pinned CRD YAML fixtures |
| L2 | API Dry-Run | Nightly, ~10m | `kubectl --dry-run=server` rejects manifests the dashboard creates |
| L3 | Integration Smoke | Nightly, ~5m | Full TrainJob lifecycle: create, pause, resume, immutability, delete |

Layer 1 runs in `odh-dashboard` on every PR. Layers 2 and 3 run in [kueue-sentinel-nightly.yml](../.github/workflows/kueue-sentinel-nightly.yml).

## Incidents and layer coverage

### API version mismatch — `RHOAIENG-58488`

**What happened:** Kueue promoted storage API from `v1beta1` to `v1beta2`. The dashboard still called `v1beta1`. Pausing and resuming RayJobs failed silently on Kueue 1.3.x clusters.

**Fix:** Updated types, added contract tests, pinned CRD fixtures.

**Coverage:** Layer 1 — Contract Tests

### Immutable field — `RHOAIENG-88520`

**What happened:** Trainer v2.3.0 made `spec.trainer` immutable after job creation. The dashboard PATCHed that field on scale. The cluster rejected it silently; the UI showed success.

**Fix:** Removed PATCH-based scale path, updated types and mocks, Layer 3 asserts immutability.

**Coverage:** Layer 2 + Layer 3

### Webhook label enforcement

**What happened:** Kueue's admission webhook requires `kueue.x-k8s.io/queue-name` on managed workloads. Missing or wrong labels cause silent rejection at the cluster.

**Fix:** Dry-run validation for every workload type; manifests derived from dashboard YAML factories, not hand-written test files.

**Coverage:** Layer 2 — API Dry-Run

### HardwareProfile race condition — `RHOAIENG-85382`

**What happened:** Timing issue between Kueue admission webhook and scheduler caused priority classes to not always apply on HardwareProfile workloads. Intermittent, invisible in unit tests.

**Fix:** Layer 3 validates full admission lifecycle including priority class application.

**Coverage:** Layer 3 — Integration Smoke

## Running

- **Workflow:** [kueue-sentinel-nightly.yml](../.github/workflows/kueue-sentinel-nightly.yml)
- **Schedule:** 07:30 UTC daily
- **Manual run:** Actions → Kueue Sentinel → Run workflow
- **Sample run:** https://github.com/Lucifergene/odh-automations/actions/runs/33922658480

Each run posts to Slack with Kueue and Trainer versions tested, per-layer pass/fail, and a link to the workflow run.

## Secrets

| Secret | Purpose |
|--------|---------|
| `KUEUE_SENTINEL_SLACK_WEBHOOK_URL` | Slack Workflow Builder webhook |

## Numbers

- **4** incidents that drove the design
- **3** test layers
- **~15 min** per nightly run
- **13** automated assertions per run (6 dry-run + 7 integration)
- **2** upstream repos monitored: Kueue and Kubeflow Trainer
