#!/bin/bash
set -u
inventory=$1
secrets=$2
status_file=${3:-/tmp/course-ansible.exit}
cd "$(dirname "$0")/../ansible" || exit 1
ansible-playbook -i "$inventory" site.yml -e "@$secrets"
result=$?
printf '%s\n' "$result" > "$status_file"
exit "$result"
