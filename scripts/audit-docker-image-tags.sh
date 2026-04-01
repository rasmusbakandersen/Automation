find . -maxdepth 3 -type f \( -name 'docker-compose.yml' -o -name 'compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' \) -exec grep -h '^\s*image:' {} + 2>/dev/null | sed 's/.*image:\s*//' | tr -d '"'"'" | sed 's/\s*#.*//' | sort -u | while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  if [[ "$raw" == *'${'* || "$raw" == *'$'* ]]; then echo -e "\e[33m⚠ $raw\e[0m — uses variable, check manually"; continue; fi
  if [[ "$raw" == *@sha256:* ]]; then img="${raw%%@*}"; tag="@digest"; elif [[ "$raw" == *:* ]]; then tag="${raw##*:}"; img="${raw%:*}"; else img="$raw"; tag="latest"; fi
  [[ "$img" == lscr.io/* ]] && img="${img#lscr.io/}"
  repo="$img"; [[ "$repo" != */* ]] && repo="library/$repo"
  printf "%-45s %-20s" "$img" ":$tag"
  if [[ "$img" == ghcr.io/* ]]; then echo "  (ghcr — check manually)"; continue; fi
  latest=$(curl -sf --max-time 8 "https://hub.docker.com/v2/repositories/${repo}/tags/?page_size=25&ordering=last_updated" 2>/dev/null | jq -r '[.results[]? | select(.name | test("^v?[0-9]+\\.[0-9]+") ) | select(.name | test("rc|beta|alpha|dev|nightly") | not)][0].name // empty')
  if [[ -z "$latest" ]]; then echo "  (could not fetch)";
  elif [[ "$tag" == "latest" ]]; then echo -e "  \e[33m⚠ unpinned\e[0m — latest stable: \e[1m$latest\e[0m";
  elif [[ "$latest" != "$tag" ]]; then echo -e "  \e[33m⚠ update available → \e[1m$latest\e[0m";
  else echo -e "  \e[32m✓ up to date\e[0m"; fi
done
