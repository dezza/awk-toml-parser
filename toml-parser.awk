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
  stderr("       awk -f toml-parser.awk FILE --query SECTION KEY DEFAULT ...")
  failed = 1
  exit 2
}

function parse_args(    position, count) {
  if (ARGC < 2)
    usage()

  file = ARGV[1]

  if (ARGC >= 3 && ARGV[2] == "--query") {
    count = ARGC - 3
    if (count < 3 || count % 3 != 0)
      usage()

    batch_mode = 1

    for (position = 0; position < count; position += 3) {
      batch_section[++batch_count] = ARGV[3 + position]
      batch_key[batch_count] = ARGV[4 + position]
      batch_default[batch_count] = ARGV[5 + position]
    }

    for (position = 2; position < ARGC; position++)
      delete ARGV[position]

    return
  }

  if (ARGC == 2)
    return

  if (ARGC != 4 && ARGC != 5)
    usage()

  query_mode = 1
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

function find_unquoted(text, wanted,    character, position, quote) {
  quote = ""

  for (position = 1; position <= length(text); position++) {
    character = substr(text, position, 1)

    if (quote != "") {
      if (quote == "\"" && character == "\\")
        position++
      else if (character == quote)
        quote = ""
      continue
    }

    if (character == "\"" || character == "'") {
      quote = character
      continue
    }

    if (character == wanted)
      return position
  }

  return 0
}

function strip_comment(text,    position) {
  position = find_unquoted(text, "#")
  return position ? substr(text, 1, position - 1) : text
}

function array_complete(text) {
  return find_unquoted(text, "]") != 0
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
  return text != "" && text !~ /,/ && text !~ /[[:cntrl:]]/
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

function dotted_key(prefix, name) {
  return prefix == "" ? name : prefix "." name
}

function emit(name, value,    key, position) {
  if (batch_mode) {
    key = dotted_key(section, name)

    for (position = 1; position <= batch_count; position++)
      if (!batch_found[position] && \
          dotted_key(batch_section[position], batch_key[position]) == key) {
        batch_value[position] = value
        batch_found[position] = 1
      }

    return
  }

  if (query_mode) {
    if (dotted_key(section, name) == \
        dotted_key(wanted_section, wanted_key)) {
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

function print_batch(    position) {
  for (position = 1; position <= batch_count; position++)
    if (batch_found[position])
      print batch_value[position]
    else
      print batch_default[position]
}

BEGIN {
  array_line = ""
  failed = 0
    found = 0
    batch_mode = 0
    query_mode = 0
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

  if (!failed && batch_mode) {
    print_batch()
  } else if (!failed && query_mode && !found && have_default)
    print default_value
}
