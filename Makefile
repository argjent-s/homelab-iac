# Raccourcis pour les exécutions manuelles depuis le LXC ctl-iac (utilisateur iac).
# Le token Proxmox est chargé depuis ~/.config/iac/proxmox.env (voir docs/GUIDE.md).

TF := terraform -chdir=terraform

.PHONY: help init plan apply inventory ansible deploy check destroy

help: ## Affiche cette aide
	@grep -E "^[a-z]+:.*##" $(MAKEFILE_LIST) | awk -F ":.*## " "{printf \"  %-10s %s\\n\", \$$1, \$$2}"

init: ## Initialise Terraform (providers + backend)
	$(TF) init

plan: ## Affiche les changements prévus
	$(TF) plan

apply: ## Applique les changements (demande confirmation)
	$(TF) apply

inventory: ## Génère l inventaire Ansible depuis l état Terraform
	$(TF) output -raw ansible_inventory > ansible/inventory/hosts.yml

ansible: inventory ## Configure les conteneurs avec Ansible
	cd ansible && ansible-playbook site.yml

deploy: apply ansible ## apply + ansible

check: ## Contrôles locaux identiques à la CI (fmt, validate, lint)
	$(TF) fmt -check -recursive
	$(TF) validate
	cd ansible && ansible-lint

destroy: ## Détruit les conteneurs gérés par Terraform (demande confirmation)
	$(TF) destroy
