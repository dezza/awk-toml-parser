# Makefile: GNU Make; target: Linux
TFW_DIR ?= deps/test-framework
-include $(TFW_DIR)/Makefile

.PHONY: check coverage test update-test-framework \
	toml-parser-check-submodule toml-parser-update

test: tfw-test
coverage: tfw-cov
update-test-framework: tfw-update

toml-parser-check-submodule:
	if ! super=$$(git rev-parse --show-superproject-working-tree \
		2>/dev/null) || [ -z "$$super" ]; then \
		printf '%s\n' 'error: must be a Git submodule' >&2; \
		exit 1; \
		fi

toml-parser-update: toml-parser-check-submodule
	super=$$(git rev-parse --show-superproject-working-tree) && \
				rel=$$(git rev-parse --show-prefix) && \
				git -C "$$super" -c protocol.file.allow=always \
				submodule update --remote --merge -- "$${rel%/}"
