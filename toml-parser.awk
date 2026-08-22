# Parse or query a small, strict TOML subset.
#
# Usage:
#   awk -f toml-parser.awk FILE
#   awk -f toml-parser.awk FILE SECTION KEY [DEFAULT]
#
# FILE mode emits repeating NUL-terminated fields:
#   SECTION\0KEY\0VALUE\0
#
# Query mode emits VALUE followed by a newline.

function stderr(message) {
  print message > "/dev/stderr"
  close("/dev/stderr")
}

function die(message) {
  stderr(file ":" FNR ": " message)
  failed = 1
  exit 2
}

function usage() {
  stderr("usage: awk -f toml-parser.awk FILE [SECTION KEY [DEFAULT]]")
  failed = 1
  exit 2
}

function parse_args() {
  if (ARGC != 2 && ARGC != 4 && ARGC != 5)
    usage()

  file = ARGV[1]
  query_mode = ARGC >= 4

  if (query_mode) {
    wanted_section = ARGV[2]
    wanted_key = ARGV[3]
    have_default = ARGC == 5

        if (have_default)
            default_value = ARGV[4]

        delete ARGV[2]
        delete ARGV[3]
        if (have_default)
            delete ARGV[4]
  }
}

function trim(text) {
  sub(/^[[:space:]]+/, "", text)
  sub(/[[:space:]]+$/, "", text)
  return text
}

function is_section(text) {
  return text ~ /^[[:space:]]*\[\[?[^][]+\]\]?[[:space:]]*(#.*)?$/
}

function parse_section(text,    name) {
  name = text
  sub(/^[[:space:]]*\[\[?/, "", name)
  sub(/\]\]?[[:space:]]*(#.*)?$/, "", name)
  return name
}

function is_assignment(text) {
  return text ~ /^[[:space:]]*[A-Za-z0-9_.\/~"-]+[[:space:]]*=/
}

function parse_key(text,    name) {
  name = text
  sub(/^[[:space:]]*/, "", name)
  sub(/[[:space:]]*=.*/, "", name)
  return name
}

function raw_value(text,    value) {
  value = text
  sub(/^[^=]*=[[:space:]]*/, "", value)
  return trim(value)
}

function strip_comment(text,    character, position, quote) {
  quote = ""
  for (position = 1; position <= length(text); position++) {
    character = substr(text, position, 1)
    if (quote != "") {
      if (quote == "\"" && character == "\\")
        position++
      else if (character == quote)
        quote = ""
    } else if (character == "\"" || character == "'") {
      quote = character
    } else if (character == "#") {
      return substr(text, 1, position - 1)
    }
  }
  return text
}

function array_complete(text,    character, position, quote) {
  quote = ""
  for (position = 1; position <= length(text); position++) {
    character = substr(text, position, 1)
    if (quote != "") {
      if (quote == "\"" && character == "\\")
        position++
      else if (character == quote)
        quote = ""
    } else if (character == "\"" || character == "'") {
      quote = character
    } else if (character == "]") {
      return 1
    }
  }
  return 0
}

function string_length(text) {
  if (!match(text, /^("([^"\\]|\\["\\nrt])*"|'[^']*')/))
    return 0
  return RLENGTH
}

function is_string(text,    size) {
  size = string_length(text)
  return size && substr(text, size + 1) ~ /^[[:space:]]*(#.*)?$/
}

function parse_string(text,    quote, value, result, position, character) {
  quote = substr(text, 1, 1)
  value = substr(text, 2)
  sub(quote "[[:space:]]*(#.*)?$", "", value)

  if (quote == "'")
    return value

  result = ""
  for (position = 1; position <= length(value); position++) {
    character = substr(value, position, 1)
    if (character != "\\") {
      result = result character
      continue
    }

    character = substr(value, ++position, 1)
    if (character == "n")
      result = result "\n"
    else if (character == "r")
      result = result "\r"
    else if (character == "t")
      result = result "\t"
    else
      result = result character
  }
  return result
}

function is_boolean(text) {
  return text ~ /^(true|false)[[:space:]]*(#.*)?$/
}

function is_bare(text) {
  return text ~ /^[A-Za-z0-9_+@.\/:=~${}-]+[[:space:]]*(#.*)?$/
}

function parse_atom(text,    value) {
  value = text
  sub(/[[:space:]]*(#.*)?$/, "", value)
  return value
}

function is_array(text) {
  return text ~ /^\[.*\][[:space:]]*(#.*)?$/
}

function valid_array_item(text) {
  return text ~ /^[A-Za-z0-9_+@.=:\/~${}"-]+$/
}

function array_body(text,    body) {
  body = text
  sub(/^\[[[:space:]]*/, "", body)
  sub(/[[:space:]]*\][[:space:]]*(#.*)?$/, "", body)
  return body
}

function parse_array(text,    rest, result, item, size) {
  rest = trim(array_body(text))
  result = ""

  while (rest != "") {
    size = string_length(rest)
    if (!size)
      die("invalid array")

    item = substr(rest, 1, size)
    item = parse_string(item)
    if (!valid_array_item(item))
      die("invalid array value")

    result = result (result == "" ? "" : ",") item
    rest = trim(substr(rest, size + 1))

    if (rest == "")
      break

    if (substr(rest, 1, 1) != ",")
      die("invalid array")

    rest = trim(substr(rest, 2))
  }

  return result
}

function parse_value(text) {
  if (is_string(text))
    return parse_string(text)

  if (is_boolean(text))
    return parse_atom(text)

  if (is_array(text))
    return parse_array(text)

  if (is_bare(text))
    return parse_atom(text)

  die("unsupported value")
}

function put_field(value) {
  printf "%s%c", value, 0
}

function emit(name, value) {
  if (query_mode) {
    if (section == wanted_section && name == wanted_key) {
      print value
      found = 1
      exit
    }
    return
  }

  put_field(section)
  put_field(name)
  put_field(value)
}

BEGIN {
  array_line = ""
  failed = 0
    found = 0
    section = ""
    parse_args()
}

{
  if (array_line != "") {
    array_line = array_line " " trim(strip_comment($0))
    if (!array_complete(array_line))
      next
    $0 = array_line
    array_line = ""
  }

  if ($0 ~ /^[[:space:]]*(#.*)?$/)
    next

  if (is_section($0)) {
    section = parse_section($0)
    next
  }

  if (!is_assignment($0))
    die("unsupported syntax")

  current_value = raw_value($0)
  if (current_value ~ /^\[/ && !array_complete(current_value)) {
    array_line = strip_comment($0)
    next
  }

  emit(parse_key($0), parse_value(current_value))
}

END {
  if (!failed && array_line != "")
    die("unterminated array")
  if (!failed && query_mode && !found && have_default)
    print default_value
}
