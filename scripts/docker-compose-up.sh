###
###     This script finds all docker compose files on a path and “ups” them, so they're running
###




find /home/rasmus/docker \
 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) \
 | while read -r compose_file; do
     project_dir="$(dirname "$compose_file")"
     echo "Starting $project_dir"
     ( cd "$project_dir" && docker compose up -d )
   done

