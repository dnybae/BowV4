#!/bin/bash
# Bow calls budget categories "envelopes". This fails if user-facing text says "category",
# except where it names YNAB's concept (the line mentions YNAB) or is YNAB CSV fixture data.
cd "$(dirname "$0")/.."
matches=$(grep -rniE '"[^"]*categor[^"]*"' App --include='*.swift' \
  | grep -viE 'ynab|Category Group,Category')
if [ -n "$matches" ]; then
  echo "Use \"envelope\" instead of \"category\" in user-facing text:"
  echo "$matches"
  exit 1
fi
echo "Terminology check passed"
