# Makefile: GNU Make; target: Linux
-include deps/test-framework/Makefile

.PHONY: check test test-posix-awk update toml-parser-check \
	toml-parser-check-submodule toml-parser-update

TOML_PARSER_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
TEST_FRAMEWORK ?= $(TOML_PARSER_DIR)/deps/test-framework

check: toml-parser-check
update: toml-parser-update

# deps/test-framework
test: test-framework-test
update-test-framework: test-framework-update

toml-parser-check:
	awk -f toml-parser.awk /dev/null >/dev/null

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
