# Every target runs through `mise exec` so the pinned tool versions in
# mise.toml are used, whatever is installed globally.
RUN := mise exec --

.PHONY: help tools up down stop start status cluster git bootstrap openbao-config \
        bao-login argocd-password bao-password push validate

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

tools: ## Install pinned CLIs (opentofu, kubectl, helm, kind, argocd, bao)
	mise install

up: ## Build the whole lab (about 5-8 minutes the first time)
	$(RUN) scripts/up.sh

down: ## Delete the cluster, Gitea and all local state
	$(RUN) scripts/down.sh

stop: ## Pause the lab and free Docker memory (keeps all data)
	$(RUN) scripts/stop.sh

start: ## Resume a stopped lab
	$(RUN) scripts/start.sh

status: ## Show Argo CD apps and URLs
	$(RUN) scripts/status.sh

# --- Individual steps, for following the docs one layer at a time ---------

cluster: ## Step 1: create the kind cluster (stack 00)
	$(RUN) scripts/tofu.sh 00-cluster apply

git: ## Step 2: start Gitea and push this repo
	$(RUN) scripts/git-server.sh

bootstrap: ## Step 3: secret zero + Argo CD + root app (stack 10)
	TF_VAR_git_token="$$(cat .secrets/gitea-argocd-token)" $(RUN) scripts/tofu.sh 10-bootstrap apply

bao-login: ## Get an OpenBao token for stack 20
	$(RUN) scripts/bao-login.sh

openbao-config: ## Step 4: configure OpenBao (stack 20)
	$(RUN) bash -c 'source scripts/env.sh && scripts/tofu.sh 20-openbao-config apply'

# --- Helpers ---------------------------------------------------------------

argocd-password: ## Print the Argo CD admin password
	@$(RUN) bash -c 'source scripts/env.sh && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo'

bao-password: ## Print the OpenBao tofu-admin password
	@$(RUN) bash -c 'source scripts/env.sh && kubectl -n openbao get secret openbao-bootstrap-admin -o jsonpath="{.data.INITIAL_ADMIN_PASSWORD}" | base64 -d; echo'

push: ## Push your commits to Gitea; Argo CD syncs them within a minute
	git push origin HEAD

validate: ## What CI runs: fmt, validate, render and schema-check manifests
	$(RUN) scripts/validate.sh
