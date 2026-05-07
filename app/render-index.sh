#!/bin/sh
set -eu

template=/usr/share/nginx/templates/index.template.html
output=/usr/share/nginx/html/index.html

task_arn="local-task"
container_instance_arn="local-container-instance"
availability_zone="local"
hostname_value="$(hostname)"
app_version="${APP_VERSION:-dev}"
image_tag="${IMAGE_TAG:-local}"

json_value() {
  key="$1"
  file="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

if [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
  metadata_file=/tmp/ecs-task-metadata.json
  if wget -q -O "$metadata_file" "$ECS_CONTAINER_METADATA_URI_V4/task"; then
    task_arn="$(json_value TaskARN "$metadata_file")"
    container_instance_arn="$(json_value ContainerInstanceARN "$metadata_file")"
    availability_zone="$(json_value AvailabilityZone "$metadata_file")"
  fi
fi

task_arn="${task_arn:-unknown-task}"
container_instance_arn="${container_instance_arn:-unknown-container-instance}"
availability_zone="${availability_zone:-unknown-az}"
task_id="${task_arn##*/}"

escape_html() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g' \
    | sed 's/</\&lt;/g' \
    | sed 's/>/\&gt;/g' \
    | sed 's/"/\&quot;/g'
}

sed \
  -e "s#__APP_VERSION__#$(escape_html "$app_version")#g" \
  -e "s#__IMAGE_TAG__#$(escape_html "$image_tag")#g" \
  -e "s#__TASK_ID__#$(escape_html "$task_id")#g" \
  -e "s#__TASK_ARN__#$(escape_html "$task_arn")#g" \
  -e "s#__CONTAINER_INSTANCE_ARN__#$(escape_html "$container_instance_arn")#g" \
  -e "s#__AVAILABILITY_ZONE__#$(escape_html "$availability_zone")#g" \
  -e "s#__HOSTNAME__#$(escape_html "$hostname_value")#g" \
  "$template" > "$output"
