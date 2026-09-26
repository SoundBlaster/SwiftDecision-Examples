ASC ?= asc
ASC_APP ?=
ASC_VERSION ?=
ASC_PLATFORM ?= IOS
ASC_METADATA_DIR ?= ./metadata
ASC_REVIEW_DIR ?= ./.asc/metadata/review

.DEFAULT_GOAL := help
.PHONY: help asc-auth asc-status asc-builds asc-review-doctor asc-validate \
	asc-metadata-validate asc-metadata-plan _require-asc-app _require-asc-version

help: ## Show available App Store Connect shortcuts.
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "%-24s %s\n", $$1, $$2}'

_require-asc-app:
	@test -n "$(ASC_APP)" || { echo "Set ASC_APP to the App Store Connect app ID, bundle ID, or exact app name." >&2; exit 2; }

_require-asc-version:
	@test -n "$(ASC_VERSION)" || { echo "Set ASC_VERSION to the App Store version (for example, 1.0.0)." >&2; exit 2; }

asc-auth: ## Validate the locally configured asc credentials.
	$(ASC) auth status --validate --output table

asc-status: _require-asc-app ## Show the App Store Connect release dashboard.
	$(ASC) status --app "$(ASC_APP)" --output table

asc-builds: _require-asc-app ## List uploaded iOS builds and their processing states.
	$(ASC) builds list --app "$(ASC_APP)" --platform "$(ASC_PLATFORM)" --paginate --output table

asc-review-doctor: _require-asc-app _require-asc-version ## Explain App Review blockers for a version.
	$(ASC) review doctor --app "$(ASC_APP)" --version "$(ASC_VERSION)" --platform "$(ASC_PLATFORM)" --output table

asc-validate: _require-asc-app _require-asc-version ## Check App Store submission readiness (read-only).
	$(ASC) validate --app "$(ASC_APP)" --version "$(ASC_VERSION)" --platform "$(ASC_PLATFORM)" --output table

asc-metadata-validate: ## Validate local metadata files without contacting App Store Connect.
	@test -d "$(ASC_METADATA_DIR)" || { echo "Metadata directory not found: $(ASC_METADATA_DIR)" >&2; exit 2; }
	$(ASC) metadata validate --dir "$(ASC_METADATA_DIR)" --output table

asc-metadata-plan: _require-asc-app _require-asc-version ## Compare local metadata and save a review plan locally.
	@test -d "$(ASC_METADATA_DIR)" || { echo "Metadata directory not found: $(ASC_METADATA_DIR)" >&2; exit 2; }
	$(ASC) metadata plan --app "$(ASC_APP)" --version "$(ASC_VERSION)" --platform "$(ASC_PLATFORM)" --dir "$(ASC_METADATA_DIR)" --review-dir "$(ASC_REVIEW_DIR)" --output table
