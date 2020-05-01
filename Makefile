# Variables
CURRENT_DIRECTORY := $(shell pwd)
INSTALL_DIRECTORY := $(CURRENT_DIRECTORY)/.venv
PYTHON_FILES := $(shell find * -path .venv -prune -o -type f -name "*.py" -print)
SHELLSPEC_VERSION := "0.20.2"

# install git hook with heredoc needs the following option
.ONESHELL:

# Colors
RESET := $(shell tput sgr0)
RED := $(shell tput setaf 1)
GREEN := $(shell tput setaf 2)

# Commands
SHELLSPEC_CMD := $(INSTALL_DIRECTORY)/bin/shellspec

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo
	@echo "Possible targets:"
	@echo "- all                Install ven and deps"
	@echo "- bash_unit_test     Run unit tests on bash scripts"
	@echo "- cleanall           Remove the virtualenv"
	@echo ""

.PHONY: all
all:
	@if [ ! -d $(INSTALL_DIRECTORY) ]; \
	then \
		mkdir -p $(INSTALL_DIRECTORY); \
		curl -fsSL https://git.io/shellspec | sh -s $(SHELLSPEC_VERSION) -p $(INSTALL_DIRECTORY) -y; \
	fi
	@cat <<EOF > .git/hooks/pre-commit
	#!/bin/bash
	make bash_unit_test
	if [[ \$$? != 0 ]];
	then
	echo "\$$(tput setaf 1) Nothing has been commited because of bash unit tests, please fix it according to the comments above \$$(tput sgr0)"
	exit 1
	fi
	EOF
	@chmod a+x .git/hooks/pre-commit

.PHONY: bash_unit_test
bash_unit_test:
	@echo "${GREEN}Bash Script unit tests...${RESET}";
	@for f in $(shell find * -type d -name "spec"); do \
		cd  $${f}/../; \
		pwd; \
		${SHELLSPEC_CMD} -s bash || exit 1; \
		cd -; \
	done

.PHONY: cleanall
cleanall:
	rm -rf .venv
