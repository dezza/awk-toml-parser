#!/bin/sh

AWK=${AWK:-awk}

toml_get() {
  "$TEST_PROJECT_DIR/toml-get.sh" "$@"
}

toml_parse() {
  "$AWK" ${AWKFLAGS-} -f "$TEST_PROJECT_DIR/toml-parser.awk" "$@" |
    tr '\000' '%'
}

quietly() {
  "$@" 2>/dev/null
}

assert_query() {
  description=$1
  expected=$2
  shift 2
  actual=$(toml_get "$@")
  assert_equal "$description" "$actual" "$expected"
}

test_query_values() {
  config=$TEST_TMPDIR/values.toml
  printf '%s\n' \
    '# comment' \
    'root-key = ${ROOT}/bare$value # trailing comment' \
    '[group.one-two] # section comment' \
    'string = "quoted \"text\" and \\ slash"' \
    'lines = "first\nsecond"' \
    'tab = "left\tright"' \
    'enabled = true' \
    'disabled = false' \
    'items = ["$ONE", "${TWO}/value"]' \
    'empty = []' >"$config"

  assert_query 'bare value and comments' '${ROOT}/bare$value' \
    "$config" '' root-key
  assert_query 'quoted string escapes' 'quoted "text" and \ slash' \
    "$config" group.one-two string
  assert_query 'newline escape' "$(printf 'first\nsecond')" \
    "$config" group.one-two lines
  assert_query 'tab escape' "$(printf 'left\tright')" \
    "$config" group.one-two tab
  assert_query 'true boolean' true "$config" group.one-two enabled
  assert_query 'false boolean' false "$config" group.one-two disabled
  assert_query 'string array' '$ONE,${TWO}/value' \
    "$config" group.one-two items
  assert_query 'empty array' '' "$config" group.one-two empty
  assert_query 'default value' fallback \
    "$config" group.one-two missing fallback
  assert_query 'missing file default' fallback \
    "$TEST_TMPDIR/missing.toml" any key fallback
}

test_parse_fields() {
  config=$TEST_TMPDIR/fields.toml
  printf '%s\n' \
    'root = value' \
    '' \
    '[first]' \
    'key = "one"' \
    '[second.part]' \
    'key = "two"' >"$config"

  actual=$(toml_parse "$config")
  assert_equal 'root and section fields' "$actual" \
    '%root%value%first%key%one%second.part%key%two%'
}

test_errors() {
  config=$TEST_TMPDIR/invalid.toml

  printf '%s\n' '[invalid' >"$config"
  assert_status 'rejects invalid section' 2 quietly \
    "$AWK" ${AWKFLAGS-} -f "$TEST_PROJECT_DIR/toml-parser.awk" "$config"

  printf '%s\n' 'value = [bare]' >"$config"
  assert_status 'rejects unsupported value' 2 quietly \
    toml_get "$config" '' value

  printf '%s\n' 'value = ["invalid!"]' >"$config"
  assert_status 'rejects invalid array item' 2 quietly \
    toml_get "$config" '' value

  assert_status 'rejects invalid parser invocation' 2 quietly \
    "$AWK" ${AWKFLAGS-} -f "$TEST_PROJECT_DIR/toml-parser.awk"
  assert_status 'rejects invalid query invocation' 2 quietly \
    "$TEST_PROJECT_DIR/toml-get.sh" "$config"
}

test_case 'query values' test_query_values
test_case 'parse fields' test_parse_fields
test_case 'errors' test_errors
