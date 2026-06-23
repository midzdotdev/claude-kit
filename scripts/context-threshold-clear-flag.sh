#!/usr/bin/env bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
rm -f "/tmp/claude-ctx-warned-$session_id"
