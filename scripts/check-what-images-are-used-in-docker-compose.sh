#!/usr/bin/env bash
# Usage: ./list-compose-images.sh /path/to/base (default: .)

set -euo pipefail

BASE_DIR="${1:-.}"

find "$BASE_DIR" \
  \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) \
  | while read -r compose_file; do
    (
      cd "$(dirname "$compose_file")"
      docker compose -f "$(basename "$compose_file")" config 2>/dev/null \
        | awk '
            $1 == "image:" {
              img = $2
              for (i = 3; i <= NF; i++) img = img " " $i
              print img
            }
          '
    )
done | sort -u
