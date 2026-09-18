#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    "usage: ${0##*/} FILE SECTION KEY [DEFAULT]" \
    "       ${0##*/} FILE --query SECTION KEY DEFAULT [SECTION KEY DEFAULT]..."
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

if [ "$#" -lt 3 ]; then
  usage >&2; exit 2
fi

case $1 in
  -*) file=./$1; shift; set -- "$file" "$@";;
esac

if [ "$2" = "--query" ]; then
  if [ $(( ($# - 2) % 3 )) -ne 0 ]; then
    usage >&2; exit 2
  fi

  if [ ! -r "$1" ]; then
    shift 2
    while [ "$#" -ge 3 ]; do
      printf '%s\n' "$3"
      shift 3
    done
    exit 0
  fi

  exec "${AWK:-awk}" ${AWKFLAGS-} -f "${0%/*}/toml-parser.awk" "$@"
fi

if [ "$#" -gt 4 ]; then
  usage >&2; exit 2
fi

if [ ! -r "$1" ]; then
  printf '%s\n' "${4-}"
  exit 0
fi

exec "${AWK:-awk}" ${AWKFLAGS-} -f "${0%/*}/toml-parser.awk" "$@"
