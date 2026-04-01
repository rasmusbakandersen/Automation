#!/bin/bash
# k8s-scan-24-hour.sh
# Scans all K3s pods for errors in the last 24h
# Output format: === podname/container (image) ===\nerror lines...
# Compatible with the existing n8n Docker log condensing workflow

SINCE_HOURS=24
MAX_LINES=100
SKIP_NS="kube-system kube-public kube-node-lease"
ERROR_PATTERN='[Ee]rror|[Ff]atal|[Pp]anic|[Ee]xception|[Ff]ail|[Cc]ritical|[Cc]rash|OOM|[Kk]illed|[Tt]imeout|[Rr]efused|[Dd]enied|[Uu]nable|[Cc]annot'

output=""

# --- Phase 1: Find problem pods (restarts, bad phase, waiting states) ---
problem_pods=$(kubectl get pods --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
skip = set('${SKIP_NS}'.split())
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns in skip:
        continue
    name = pod['metadata']['name']
    phase = pod['status'].get('phase', 'Unknown')
    is_problem = phase in ('Failed', 'Unknown', 'Pending')
    for cs in pod['status'].get('containerStatuses', []):
        if cs.get('restartCount', 0) > 0:
            is_problem = True
        state = cs.get('state', {})
        if 'waiting' in state:
            reason = state['waiting'].get('reason', '')
            if reason in ('CrashLoopBackOff', 'Error', 'OOMKilled', 'ImagePullBackOff', 'ErrImagePull', 'CreateContainerConfigError'):
                is_problem = True
    if is_problem:
        images = [c.get('image', 'unknown') for c in pod['spec'].get('containers', [])]
        print(f\"{ns}|{name}|{','.join(images)}|{phase}\")
" 2>/dev/null)

# Collect previous logs from problem pods
while IFS='|' read -r ns pod_name images phase; do
    [ -z "$ns" ] && continue
    prev_logs=$(kubectl logs -n "$ns" "$pod_name" --previous --since="${SINCE_HOURS}h" --tail="$MAX_LINES" 2>/dev/null | \
        grep -iE "$ERROR_PATTERN" | tail -"$MAX_LINES")
    if [ -n "$prev_logs" ]; then
        output+="=== ${pod_name} (${images}) [previous/${phase}] ===
${prev_logs}
"
    fi
done <<< "$problem_pods"

# --- Phase 2: Scan all non-system pods for error lines in current logs ---
all_containers=$(kubectl get pods --all-namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
skip = set('${SKIP_NS}'.split())
for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    if ns in skip:
        continue
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        print(f\"{ns}|{name}|{c['name']}|{c.get('image', 'unknown')}\")
" 2>/dev/null)

while IFS='|' read -r ns pod_name container image; do
    [ -z "$ns" ] && continue
    error_logs=$(kubectl logs -n "$ns" "$pod_name" -c "$container" --since="${SINCE_HOURS}h" --tail="$MAX_LINES" 2>/dev/null | \
        grep -iE "$ERROR_PATTERN" | tail -"$MAX_LINES")
    if [ -n "$error_logs" ]; then
        output+="=== ${pod_name}/${container} (${image}) ===
${error_logs}
"
    fi
done <<< "$all_containers"

# --- Output ---
if [ -z "$output" ]; then
    echo "No errors found"
else
    echo "$output"
fi
