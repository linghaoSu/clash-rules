#!/usr/bin/env bash

set -euo pipefail

upstream_source="${1:?usage: generate-claude-rules.sh <upstream-url-or-file> [output-file] [fallback-url-or-file]}"
output_file="${2:-claude.txt}"
fallback_source="${3:-}"

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

upstream_file="${temp_dir}/upstream.yaml"
generated_file="${temp_dir}/claude.txt"

fetch_rules() {
  local source="$1"
  local destination="$2"

  case "${source}" in
    http://*|https://*)
      curl --fail --silent --show-error --location \
        --connect-timeout 10 --max-time 30 \
        --retry 2 --retry-all-errors --retry-max-time 60 \
        "${source}" --output "${destination}"
      ;;
    *)
      if [[ ! -f "${source}" ]]; then
        echo "Claude rules file not found: ${source}" >&2
        return 1
      fi
      cp "${source}" "${destination}"
      ;;
  esac

  if ! grep -Eq '^payload:[[:space:]]*$' "${destination}"; then
    echo "Claude rules source does not contain a Clash payload: ${source}" >&2
    return 1
  fi
}

if ! fetch_rules "${upstream_source}" "${upstream_file}"; then
  if [[ -z "${fallback_source}" ]]; then
    echo "Unable to fetch upstream Claude rules" >&2
    exit 1
  fi
  echo "Primary Claude rules source failed; trying fallback" >&2
  if ! fetch_rules "${fallback_source}" "${upstream_file}"; then
    echo "Unable to fetch upstream Claude rules from primary or fallback" >&2
    exit 1
  fi
fi

rule_count="$(grep -Ec '^[[:space:]]*-[[:space:]]*[^#[:space:]]' "${upstream_file}")"
if (( rule_count < 20 )); then
  echo "Refusing to publish an unexpectedly small Claude ruleset (${rule_count} rules)" >&2
  exit 1
fi

{
  printf '%s\n' \
    '# Generated automatically; do not edit the release copy.' \
    '# Source: https://github.com/VPSDance/ai-proxy-rules' \
    '#' \
    '# VPSDance/ai-proxy-rules license:' \
    '# MIT License' \
    '#' \
    '# Copyright (c) 2026 VPSDance' \
    '#' \
    '# Permission is hereby granted, free of charge, to any person obtaining a copy' \
    '# of this software and associated documentation files (the "Software"), to deal' \
    '# in the Software without restriction, including without limitation the rights' \
    '# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell' \
    '# copies of the Software, and to permit persons to whom the Software is' \
    '# furnished to do so, subject to the following conditions:' \
    '#' \
    '# The above copyright notice and this permission notice shall be included in all' \
    '# copies or substantial portions of the Software.' \
    '#' \
    '# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR' \
    '# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,' \
    '# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE' \
    '# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER' \
    '# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,' \
    '# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE' \
    '# SOFTWARE.'
  sed -n '/^payload:[[:space:]]*$/,$p' "${upstream_file}"
} > "${generated_file}"

mv "${generated_file}" "${output_file}"
echo "Generated ${output_file} with ${rule_count} classical rules"
