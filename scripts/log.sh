#!/usr/bin/env bash

# Print an usage message to stderr.  The arguments are printed directly.
warn() {
  local message
  for message; do
    echo "${message}" >&2
  done
}

# Log an error but keep going.  Don't dump the stack or exit.
error() {
  timestamp=$(date +"[%m%d %H:%M:%S]")
  echo "!!! ${timestamp} ${1-}" >&2
  shift
  for message; do
    echo "    ${message}" >&2
  done
}

# Print out some info that isn't a top level status line
info() {
  for message; do
    echo "${message}"
  done
}

# Print a status line.  Formatted to show up in a stream of output.
status() {
  timestamp=$(date +"[%m%d %H:%M:%S]")
  echo "+++ ${timestamp} ${1}"
  shift
  for message; do
    echo "    ${message}"
  done
}

# Log an error and exit.
# Args:
#   $1 Message to log with the error
#   $2 The error code to return
error_exit() {
  local message="${1:-}"
  local code="${2:-1}"

  local source_file=${BASH_SOURCE[${stack_skip}]}
  local source_line=${BASH_LINENO[$((stack_skip - 1))]}
  echo "!!! Error in ${source_file}:${source_line}" >&2
  [[ -z ${1-} ]] || {
    echo "  ${1}" >&2
  }

  echo "Exiting with status ${code}" >&2

  exit "${code}"
}

info_from_stdin() {
  local messages=()
  while read -r line; do
    messages+=("${line}")
  done

  info "${messages[@]}"
}
