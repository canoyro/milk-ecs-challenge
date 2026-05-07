#!/usr/bin/env bash
set -euo pipefail

: "${STACK_NAME:?STACK_NAME is required}"

template_file="${TEMPLATE_FILE:-ecs-webapp.yaml}"
parameters_file="${PARAMETERS_FILE:-parameters.json}"
capabilities="${CAPABILITIES:-CAPABILITY_NAMED_IAM}"

if [ -n "${CONTAINER_IMAGE:-}" ]; then
  parameter_query='.[] | select(.ParameterKey != "ContainerImage") | "\(.ParameterKey)=\(.ParameterValue)"'
else
  parameter_query='.[] | "\(.ParameterKey)=\(.ParameterValue)"'
fi

mapfile -t parameter_overrides < <(jq -r "$parameter_query" "$parameters_file")

deploy_command=(
  aws cloudformation deploy
  --stack-name "$STACK_NAME"
  --template-file "$template_file"
  --capabilities "$capabilities"
)

if [ "${#parameter_overrides[@]}" -gt 0 ]; then
  deploy_command+=(--parameter-overrides "${parameter_overrides[@]}")
fi

if [ -n "${CONTAINER_IMAGE:-}" ]; then
  deploy_command+=(ContainerImage="$CONTAINER_IMAGE")
fi

"${deploy_command[@]}"
