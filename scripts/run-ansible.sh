#!/bin/bash
set -u
inventory=$1
secrets=$2
status_file=${3:-/tmp/course-ansible.exit}
limit=${4:-all}
exec 9>/tmp/course-ansible.lock
flock -n 9 || exit 75
printf '%s\n' running > "$status_file"
cd "$(dirname "$0")/../ansible" || exit 1
ansible-playbook -i "$inventory" site.yml -e "@$secrets" --limit "$limit"
result=$?
printf '%s\n' "$result" > "$status_file"
exit "$result"
