#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    "usage: ${0##*/} FILE SECTION KEY [DEFAULT]"
}

while [ "$#" -gt 0 ]; do case $1 in
    -h|--help)
      usage; exit;;
    --)
      shift; break;;
    -*)
      printf '%s: unknown option: %s\n' "${0##*/}" "$1" >&2; exit 2;;
    *)
      break;;
esac; done

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || {
  usage >&2; exit 2
}

[ -r "$1" ] || {
  printf '%s\n' "${4-}"; exit 0
}

"${AWK:-awk}" ${AWKFLAGS-} -f "${0%/*}/toml-parser.awk" "$@"
