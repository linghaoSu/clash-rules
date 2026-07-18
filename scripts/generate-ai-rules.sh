#!/usr/bin/env bash

set -euo pipefail

upstream_source="${1:?usage: generate-ai-rules.sh <upstream-url-or-file> [custom-file] [output-file] [fallback-url-or-file]}"
custom_file="${2:-ai.txt}"
output_file="${3:-ai.txt}"
fallback_source="${4:-}"

if [[ ! -f "${custom_file}" ]]; then
  echo "Custom AI rules file not found: ${custom_file}" >&2
  exit 1
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

upstream_file="${temp_dir}/upstream.yaml"
upstream_rules_file="${temp_dir}/upstream-rules.txt"
custom_rules_file="${temp_dir}/custom-rules.txt"
rules_file="${temp_dir}/rules.txt"
generated_file="${temp_dir}/ai.txt"

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
        echo "AI rules file not found: ${source}" >&2
        return 1
      fi
      cp "${source}" "${destination}"
      ;;
  esac

  if ! grep -Eq '^payload:[[:space:]]*$' "${destination}"; then
    echo "AI rules source does not contain a Clash payload: ${source}" >&2
    return 1
  fi
}

if ! fetch_rules "${upstream_source}" "${upstream_file}"; then
  if [[ -z "${fallback_source}" ]]; then
    echo "Unable to fetch upstream AI rules" >&2
    exit 1
  fi
  echo "Primary AI rules source failed; trying fallback" >&2
  if ! fetch_rules "${fallback_source}" "${upstream_file}"; then
    echo "Unable to fetch upstream AI rules from primary or fallback" >&2
    exit 1
  fi
fi

sed -n "s/^[[:space:]]*-[[:space:]]*'\([^']*\)'[[:space:]]*$/\1/p" \
  "${custom_file}" > "${custom_rules_file}"

awk '
  /^[[:space:]]*-[[:space:]]*DOMAIN-SUFFIX,/ {
    rule = $0
    sub(/^[[:space:]]*-[[:space:]]*DOMAIN-SUFFIX,/, "", rule)
    sub(/,.*/, "", rule)
    sub(/^[[:space:]]*/, "", rule)
    sub(/[[:space:]]*$/, "", rule)
    if (rule != "") print "+." rule
    next
  }
  /^[[:space:]]*-[[:space:]]*DOMAIN,/ {
    rule = $0
    sub(/^[[:space:]]*-[[:space:]]*DOMAIN,/, "", rule)
    sub(/,.*/, "", rule)
    sub(/^[[:space:]]*/, "", rule)
    sub(/[[:space:]]*$/, "", rule)
    if (rule != "") print rule
  }
' "${upstream_file}" > "${upstream_rules_file}"

LC_ALL=C sort -u -o "${custom_rules_file}" "${custom_rules_file}"
LC_ALL=C sort -u -o "${upstream_rules_file}" "${upstream_rules_file}"

custom_rule_count="$(wc -l < "${custom_rules_file}" | tr -d '[:space:]')"
upstream_rule_count="$(wc -l < "${upstream_rules_file}" | tr -d '[:space:]')"
if (( custom_rule_count == 0 )); then
  echo "Refusing to publish AI rules without local additions" >&2
  exit 1
fi
if (( upstream_rule_count < 100 )); then
  echo "Refusing to publish an unexpectedly small upstream AI ruleset (${upstream_rule_count} rules)" >&2
  exit 1
fi

LC_ALL=C sort -u "${custom_rules_file}" "${upstream_rules_file}" > "${rules_file}"

rule_count="$(wc -l < "${rules_file}" | tr -d '[:space:]')"

{
  printf '%s\n' \
    '# Generated automatically; do not edit the release copy.' \
    '# Domain rules from https://github.com/VPSDance/ai-proxy-rules are merged' \
    '# with the local additions in ai.txt on the master branch.' \
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
    '# SOFTWARE.' \
    'payload:'
  awk '{ printf "  - \047%s\047\n", $0 }' "${rules_file}"
} > "${generated_file}"

mv "${generated_file}" "${output_file}"
echo "Generated ${output_file} with ${rule_count} domain rules"
