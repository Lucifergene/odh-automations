#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="${RESULTS_DIR:-/tmp/kueue-sentinel-results}"
mkdir -p "${RESULTS_DIR}"

KUEUE_TAG="${KUEUE_TAG:?KUEUE_TAG is required}"
TRAINER_TAG="${TRAINER_TAG:?TRAINER_TAG is required}"
CRD_DIR="${CRD_DIR:-${RESULTS_DIR}/upstream-crds}"

log() {
  echo "[kueue-sentinel-setup] $*"
}

fetch_crd() {
  local url="$1"
  local dest="$2"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl --fail --silent --show-error --location -H "Authorization: Bearer ${GITHUB_TOKEN}" "${url}" -o "${dest}"
  else
    curl --fail --silent --show-error --location "${url}" -o "${dest}"
  fi
}

download_upstream_crds() {
  mkdir -p "${CRD_DIR}"
  local kueue_base="https://raw.githubusercontent.com/kubernetes-sigs/kueue/${KUEUE_TAG}/config/components/crd/bases"
  for crd in \
    kueue.x-k8s.io_workloads.yaml \
    kueue.x-k8s.io_clusterqueues.yaml \
    kueue.x-k8s.io_localqueues.yaml \
    kueue.x-k8s.io_workloadpriorityclasses.yaml \
    kueue.x-k8s.io_cohorts.yaml \
    kueue.x-k8s.io_resourceflavors.yaml; do
    fetch_crd "${kueue_base}/${crd}" "${CRD_DIR}/${crd}"
  done

  local trainer_base="https://raw.githubusercontent.com/kubeflow/trainer/${TRAINER_TAG}/manifests/base/crds"
  for crd in \
    trainer.kubeflow.org_trainjobs.yaml \
    trainer.kubeflow.org_clustertrainingruntimes.yaml; do
    fetch_crd "${trainer_base}/${crd}" "${CRD_DIR}/${crd}"
  done
}

install_kueue() {
  log "Installing Kueue ${KUEUE_TAG}"
  kubectl apply --server-side -f "https://github.com/kubernetes-sigs/kueue/releases/download/${KUEUE_TAG}/manifests.yaml"
  kubectl wait --for=condition=Available deployment/kueue-controller-manager -n kueue-system --timeout=300s
}

install_trainer() {
  log "Installing Trainer ${TRAINER_TAG}"
  local trainer_dir="${RESULTS_DIR}/trainer-src"
  rm -rf "${trainer_dir}"
  git clone --depth 1 --branch "${TRAINER_TAG}" https://github.com/kubeflow/trainer "${trainer_dir}"
  kubectl apply --server-side -k "${trainer_dir}/manifests/overlays/manager"
  kubectl wait --for=condition=Available deployment/trainer-controller-manager -n kubeflow-system --timeout=300s || \
    kubectl wait --for=condition=Available deployment/kubeflow-trainer-controller-manager -n kubeflow-system --timeout=300s
}

prepare_namespace() {
  kubectl create namespace kueue-sentinel --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace kueue-sentinel kueue.openshift.io/managed=true --overwrite
}

if [[ "${SKIP_DOWNLOAD:-false}" != "true" ]]; then
  download_upstream_crds
fi

if [[ "${SKIP_CLUSTER_SETUP:-false}" != "true" ]]; then
  install_kueue
  install_trainer
  prepare_namespace
fi

echo "setup_complete=true" > "${RESULTS_DIR}/setup.env"
