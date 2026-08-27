# Homelab deploy wrapper. Run from the repo root.
ANSIBLE   ?= ansible-playbook
VAULT     ?= --ask-vault-pass
ANSIBLE_DIR := ansible
PLAYBOOK   = cd $(ANSIBLE_DIR) && $(ANSIBLE)

.PHONY: help deploy diff check updates list

help:  ## show available targets
	@grep -hE '^[a-z%-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

deploy:  ## deploy the whole stack
	$(PLAYBOOK) deploy.yml $(VAULT)

deploy-%:  ## deploy one sdtarget, e.g. make deploy-monitoring
	$(PLAYBOOK) deploy.yml --tags $* $(VAULT)

diff:  ## dry-run the whole stack (--check --diff)
	$(PLAYBOOK) deploy.yml --check --diff $(VAULT)

check:  ## read-only unit status report
	$(PLAYBOOK) check.yml $(VAULT)

updates:  ## check container images for updates
	python3 scripts/check_updates.py

list:  ## list deployable sdtargets (tags)
	$(PLAYBOOK) deploy.yml --list-tags
