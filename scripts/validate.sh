#!/usr/bin/env bash
# The same checks CI runs (.github/workflows/*.yml), runnable locally.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> tofu fmt"
tofu fmt -check -recursive infra

echo "==> tofu validate"
for s in infra/stacks/*/; do
  (cd "$s" && export TF_DATA_DIR=.terraform-validate && tofu init -backend=false -input=false >/dev/null && tofu validate -no-color)
done

echo "==> kustomize build + kubeconform (schema check, CRDs from the community catalog)"
for o in gitops/apps/*/overlays/*/; do
  echo "   $o"
  kubectl kustomize "$o" | kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done

echo "==> Argo CD objects"
find gitops/root -name '*.yaml' -print0 | xargs -0 kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
