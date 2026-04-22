#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAX_ITEMS="${MAX_ITEMS_PER_SECTION:-5}"
TASKS_SOURCE="${TASKS_FILE:-${SRC_DIR}/templates/sample-tasks.md}"
WEATHER_LOCATION_VALUE="${WEATHER_LOCATION:-San Francisco}"

trim_nonempty() {
  awk 'NF { sub(/[[:space:]]+$/, ""); print }'
}

bulletize() {
  sed 's/^[[:space:]]*[-*][[:space:]]*//' | awk 'NF { print "- " $0 }'
}

calendar_text="$(bash "${SCRIPT_DIR}/fetch-calendar.sh")"
weather_text="$(bash "${SCRIPT_DIR}/fetch-weather.sh" "${WEATHER_LOCATION_VALUE}")"

if [[ ! -f "${TASKS_SOURCE}" ]]; then
  echo "TASKS_FILE does not exist: ${TASKS_SOURCE}" >&2
  exit 1
fi

tasks_text="$(awk '/^[[:space:]]*[-*][[:space:]]+/ { print }' "${TASKS_SOURCE}")"
if [[ -z "${tasks_text}" ]]; then
  tasks_text="$(awk 'NF { print }' "${TASKS_SOURCE}")"
fi

schedule_lines="$(printf '%s
' "${calendar_text}" | trim_nonempty | head -n "${MAX_ITEMS}")"
weather_lines="$(printf '%s
' "${weather_text}" | trim_nonempty | head -n "${MAX_ITEMS}")"
task_lines="$(printf '%s
' "${tasks_text}" | trim_nonempty | head -n "${MAX_ITEMS}")"
meeting_lines="$(printf '%s
' "${schedule_lines}" | trim_nonempty | head -n 3 | awk 'NF { print "- Review agenda, links, and attendees for: " $0 }')"

printf '# Daily Brief

'

if [[ -n "${schedule_lines}" ]]; then
  printf '## Schedule
'
  printf '%s
' "${schedule_lines}" | bulletize
  printf '
'
fi

if [[ -n "${task_lines}" ]]; then
  printf '## Priority Tasks
'
  printf '%s
' "${task_lines}" | bulletize
  printf '
'
fi

if [[ -n "${weather_lines}" ]]; then
  printf '## Weather
'
  printf '%s
' "${weather_lines}" | bulletize
  printf '
'
fi

if [[ -n "${meeting_lines}" ]]; then
  printf '## Meeting Prep
'
  printf '%s
' "${meeting_lines}"
  printf '
'
fi
