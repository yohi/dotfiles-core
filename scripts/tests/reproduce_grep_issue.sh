#!/bin/bash
set -euo pipefail
# Mocking fc-list to return nothing
echo "Testing grep with pipefail..."
count=$(echo "" | grep -i "NOT_FOUND" | wc -l)
echo "Count is $count"
