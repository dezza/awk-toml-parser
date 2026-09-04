#!/bin/sh

AWK="${AWK:-awk}"

toml_get() {
  "$TFW_PROJECT_DIR/toml-get.sh" "$@"
}

toml_parse() {
  # shellcheck disable=SC2086
  "$AWK" ${AWKFLAGS-} -f "$TFW_PROJECT_DIR/toml-parser.awk" "$@" |
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
  cat >"$config" <<-'EOF'
	# comment
	root-key = ${ROOT}/bare$value # trailing comment
	[group.one-two] # section comment
	string = "quoted \"text\" and \\ slash"
	literal = 'literal \ text'
	lines = "first\nsecond"
	tab = "left\tright"
	enabled = true
	disabled = false
	display.color = blue
	items = ["$ONE", "${TWO}/value"]
	arguments = ['--volume="$XDG_DATA_HOME"/data:/root/data']
	empty = []
	EOF

  # shellcheck disable=SC2016
  assert_query 'bare value and comments' '${ROOT}/bare$value' \
    "$config" '' root-key
  assert_query 'quoted string escapes' 'quoted "text" and \ slash' \
    "$config" group.one-two string
  assert_query 'literal string' 'literal \ text' \
    "$config" group.one-two literal
  assert_query 'newline escape' "$(printf 'first\nsecond')" \
    "$config" group.one-two lines
  assert_query 'tab escape' "$(printf 'left\tright')" \
    "$config" group.one-two tab
  assert_query 'true boolean' true "$config" group.one-two enabled
  assert_query 'false boolean' false "$config" group.one-two disabled
  assert_query 'dotted key as section lookup' blue \
    "$config" group.one-two.display color
  # shellcheck disable=SC2016
  assert_query 'string array' '$ONE,${TWO}/value' \
    "$config" group.one-two items
  # shellcheck disable=SC2016
  assert_query 'literal string array with quotes' \
    '--volume="$XDG_DATA_HOME"/data:/root/data' \
    "$config" group.one-two arguments
  assert_query 'empty array' '' "$config" group.one-two empty
  assert_query 'default value' fallback \
    "$config" group.one-two missing fallback
  assert_query 'missing file default' fallback \
    "$TEST_TMPDIR/missing.toml" any key fallback
}

test_extended_keys_and_arrays() {
  config=$TEST_TMPDIR/extended.toml
  cat >"$config" <<-'EOF'
	map."quoted-key" = 4
	[features]
	prevent_idle_sleep = true
	[group."/absolute/path"]
	items = ["first", # first item
	  '${ROOT}/second',
	  "third-value",
	] # trailing comment
	[[repeated.group]]
	enabled = true
	EOF

  assert_query 'quoted dotted key' 4 "$config" '' 'map."quoted-key"'
  assert_query 'section as dotted key lookup' true \
    "$config" '' features.prevent_idle_sleep
  # shellcheck disable=SC2016
  assert_query 'quoted section and multiline array' \
    'first,${ROOT}/second,third-value' \
    "$config" 'group."/absolute/path"' items
  assert_query 'array of tables' true "$config" repeated.group enabled
}

test_parse_fields() {
  config=$TEST_TMPDIR/fields.toml
  cat >"$config" <<-'EOF'
	root = value

	[first]
	key = "one"
	[second.part]
	key = "two"
	EOF

  actual=$(toml_parse "$config")
  assert_equal 'root and section fields' "$actual" \
    '%root%value%first%key%one%second.part%key%two%'
}

test_errors() {
  config=$TEST_TMPDIR/invalid.toml

  printf '%s\n' '[invalid' >"$config"
  # shellcheck disable=SC2086
  assert_status 'rejects invalid section' 2 quietly \
    "$AWK" ${AWKFLAGS-} -f "$TFW_PROJECT_DIR/toml-parser.awk" "$config"

  printf '%s\n' 'value = [bare]' >"$config"
  assert_status 'rejects unsupported value' 2 quietly \
    toml_get "$config" '' value

  printf '%s\n' 'value = ["invalid!"]' >"$config"
  assert_status 'rejects invalid array item' 2 quietly \
    toml_get "$config" '' value

  # shellcheck disable=SC2086
  assert_status 'rejects invalid parser invocation' 2 quietly \
    "$AWK" ${AWKFLAGS-} -f "$TFW_PROJECT_DIR/toml-parser.awk"
  assert_status 'rejects invalid query invocation' 2 quietly \
    "$TFW_PROJECT_DIR/toml-get.sh" "$config"
}

test_check() {
  # shellcheck disable=SC2086
  assert_success 'accepts empty input' quietly \
    "$AWK" ${AWKFLAGS-} -f "$TFW_PROJECT_DIR/toml-parser.awk" /dev/null
  assert_failure 'detects failure status' false
  actual=$(test_tmpdir nested)
  assert_equal 'creates relative temporary directory' \
    "$actual" "$TEST_TMPDIR/nested"
}

test_hook() {
  :
}

test_hooks() {
  assert_success 'runs hooks' true
}

test_case 'query values' test_query_values
test_case 'extended keys and arrays' test_extended_keys_and_arrays
test_case 'parse fields' test_parse_fields
test_case 'errors' test_errors
test_case 'check' test_check
test_case 'hooks' test_hooks
unset TEST_SETUP TEST_TEARDOWN
