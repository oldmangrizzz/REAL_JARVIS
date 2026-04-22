#!/usr/bin/env bash

set -euo pipefail

if [[ -n "${CALENDAR_SOURCE_FILE:-}" ]]; then
  cat "${CALENDAR_SOURCE_FILE}"
  exit 0
fi

cmd=(gcalcli)

if [[ -n "${GCALCLI_CALENDAR:-}" ]]; then
  cmd+=(--calendar "${GCALCLI_CALENDAR}")
fi

cmd+=(agenda today tomorrow)

"${cmd[@]}"
