#!/usr/bin/env bash

set -euo pipefail

if [[ -n "${WEATHER_SOURCE_FILE:-}" ]]; then
  cat "${WEATHER_SOURCE_FILE}"
  exit 0
fi

location="${1:-${WEATHER_LOCATION:-}}"

if [[ -z "${location}" ]]; then
  echo "Usage: WEATHER_LOCATION="City" bash src/scripts/fetch-weather.sh [location]" >&2
  exit 1
fi

encoded_location="$(printf "%s" "${location}" | sed 's/ /+/g')"
url="https://wttr.in/${encoded_location}?format=Location:+%l%nCondition:+%C%nTemperature:+%t%nFeels+like:+%f%nWind:+%w%nHumidity:+%h%n"

curl -fsSL --max-time 10 "${url}"
