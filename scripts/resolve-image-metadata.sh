#!/usr/bin/env bash
set -euo pipefail

: "${REPOSITORY_URI:?REPOSITORY_URI is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

sha_tag="${GITHUB_SHA::12}"
image_uri="$REPOSITORY_URI:$sha_tag"

semver_tag=""
if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  semver_tag="${GITHUB_REF_NAME#v}"
elif [ -n "${SEMANTIC_VERSION_INPUT:-}" ]; then
  semver_tag="$SEMANTIC_VERSION_INPUT"
fi

app_version="${semver_tag:-$sha_tag}"

{
  echo "sha_tag=$sha_tag"
  echo "semver_tag=$semver_tag"
  echo "app_version=$app_version"
  echo "image_uri=$image_uri"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
