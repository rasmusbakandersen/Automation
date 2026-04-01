#!/bin/bash
# ============================================================================
# K3s Cluster Full Audit Script
# ============================================================================
# Covers: Nodes, Pods, Deployments, PVCs, Longhorn, Velero, ArgoCD,
#         Cert-Manager, Sealed Secrets, DaemonSets, Resource Usage,
#         CronJobs, Ingress, Services, Events, and more.
# ============================================================================

set +e

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

section() {
  echo ""
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

subsection() {
  echo ""
  echo -e "${YELLOW}${BOLD}--- $1 ---${NC}"
}

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${BOLD}ℹ${NC} $1"; }

# Track issues
ISSUES=()
add_issue() { ISSUES+=("$1"); }

# ============================================================================
section "1. CLUSTER & NODE HEALTH"
# ============================================================================

subsection "K3s Version"
kubectl version --short 2>/dev/null || kubectl version 2>/dev/null | head -5

subsection "Node Status"
ALL_NODES_READY=true
while IFS= read -r line; do
  node=$(echo "$line" | awk '{print $1}')
  status=$(echo "$line" | awk '{print $2}')
  roles=$(echo "$line" | awk '{print $3}')
  version=$(echo "$line" | awk '{print $5}')
  if [[ "$status" == "Ready" ]]; then
    ok "$node ($roles) - $status - $version"
  else
    fail "$node ($roles) - $status - $version"
    ALL_NODES_READY=false
    add_issue "Node $node is NOT Ready"
  fi
done < <(kubectl get nodes --no-headers 2>/dev/null)

if $ALL_NODES_READY; then
  ok "All nodes are Ready"
fi

subsection "Node Resource Usage"
if kubectl top nodes &>/dev/null; then
  kubectl top nodes 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
  done
else
  warn "Metrics server not available (kubectl top not working)"
fi

subsection "Node Conditions (warnings only)"
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  conditions=$(kubectl get node "$node" -o json | jq -r '.status.conditions[] | select(.status == "True" and .type != "Ready") | "  \(.type): \(.message)"')
  if [[ -n "$conditions" ]]; then
    warn "Node $node has active conditions:"
    echo "$conditions"
    add_issue "Node $node has warning conditions"
  fi
done

# ============================================================================
section "2. NAMESPACE OVERVIEW"
# ============================================================================

kubectl get namespaces --no-headers | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  status=$(echo "$line" | awk '{print $2}')
  if [[ "$status" != "Active" ]]; then
    fail "$ns - $status"
    add_issue "Namespace $ns is $status"
  else
    info "$ns - $status"
  fi
done

# ============================================================================
section "3. POD HEALTH"
# ============================================================================

subsection "Pods NOT Running/Completed"
NOT_RUNNING=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v -E "Running|Completed|Succeeded" || true)
if [[ -z "$NOT_RUNNING" ]]; then
  ok "All pods are Running or Completed"
else
  echo "$NOT_RUNNING" | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    pod=$(echo "$line" | awk '{print $2}')
    status=$(echo "$line" | awk '{print $4}')
    fail "$ns/$pod - $status"
    add_issue "Pod $ns/$pod is $status"
  done
fi

subsection "Pod Restart Counts (>3 restarts)"
HIGH_RESTARTS=$(kubectl get pods -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if($5+0 > 3) print $0}' || true)
if [[ -z "$HIGH_RESTARTS" ]]; then
  ok "No pods with excessive restarts"
else
  echo "$HIGH_RESTARTS" | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    pod=$(echo "$line" | awk '{print $2}')
    restarts=$(echo "$line" | awk '{print $5}')
    warn "$ns/$pod - $restarts restarts"
    add_issue "Pod $ns/$pod has $restarts restarts"
  done
fi

subsection "Pods Not Fully Ready (x/y where x != y)"
kubectl get pods -A --no-headers 2>/dev/null | while IFS= read -r line; do
  ready=$(echo "$line" | awk '{print $3}')
  current=$(echo "$ready" | cut -d/ -f1)
  desired=$(echo "$ready" | cut -d/ -f2)
  status=$(echo "$line" | awk '{print $4}')
  if [[ "$current" != "$desired" && "$status" == "Running" ]]; then
    ns=$(echo "$line" | awk '{print $1}')
    pod=$(echo "$line" | awk '{print $2}')
    warn "$ns/$pod - Ready: $ready"
    add_issue "Pod $ns/$pod not fully ready ($ready)"
  fi
done

subsection "Pod Resource Usage (top consumers)"
if kubectl top pods -A --sort-by=memory &>/dev/null; then
  echo "  Top 10 by memory:"
  kubectl top pods -A --sort-by=memory 2>/dev/null | head -11 | while IFS= read -r line; do
    echo "    $line"
  done
else
  warn "Cannot get pod resource usage (metrics server unavailable)"
fi

# ============================================================================
section "4. DEPLOYMENTS & STATEFULSETS"
# ============================================================================

subsection "Deployments"
kubectl get deployments -A --no-headers 2>/dev/null | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')
  ready=$(echo "$line" | awk '{print $3}')
  current=$(echo "$ready" | cut -d/ -f1)
  desired=$(echo "$ready" | cut -d/ -f2)
  if [[ "$current" == "$desired" ]]; then
    ok "$ns/$name ($ready)"
  else
    fail "$ns/$name ($ready)"
    add_issue "Deployment $ns/$name not fully available ($ready)"
  fi
done

subsection "StatefulSets"
STS=$(kubectl get statefulsets -A --no-headers 2>/dev/null || true)
if [[ -z "$STS" ]]; then
  info "No StatefulSets found"
else
  echo "$STS" | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    ready=$(echo "$line" | awk '{print $3}')
    current=$(echo "$ready" | cut -d/ -f1)
    desired=$(echo "$ready" | cut -d/ -f2)
    if [[ "$current" == "$desired" ]]; then
      ok "$ns/$name ($ready)"
    else
      fail "$ns/$name ($ready)"
      add_issue "StatefulSet $ns/$name not fully available ($ready)"
    fi
  done
fi

subsection "DaemonSets"
kubectl get daemonsets -A --no-headers 2>/dev/null | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')
  desired=$(echo "$line" | awk '{print $3}')
  current=$(echo "$line" | awk '{print $4}')
  ready=$(echo "$line" | awk '{print $5}')
  if [[ "$desired" == "$ready" ]]; then
    ok "$ns/$name ($ready/$desired ready)"
  else
    warn "$ns/$name ($ready/$desired ready)"
    add_issue "DaemonSet $ns/$name not fully ready ($ready/$desired)"
  fi
done

# ============================================================================
section "5. PERSISTENT VOLUMES & STORAGE"
# ============================================================================

subsection "PersistentVolumes"
kubectl get pv --no-headers 2>/dev/null | while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  capacity=$(echo "$line" | awk '{print $2}')
  status=$(echo "$line" | awk '{print $5}')
  claim=$(echo "$line" | awk '{print $6}')
  if [[ "$status" == "Bound" ]]; then
    ok "$name ($capacity) -> $claim"
  elif [[ "$status" == "Released" ]]; then
    warn "$name ($capacity) - Released (orphaned)"
    add_issue "PV $name is Released/orphaned"
  else
    fail "$name ($capacity) - $status"
    add_issue "PV $name is $status"
  fi
done

subsection "PersistentVolumeClaims"
kubectl get pvc -A --no-headers 2>/dev/null | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')
  status=$(echo "$line" | awk '{print $3}')
  capacity=$(echo "$line" | awk '{print $5}')
  if [[ "$status" == "Bound" ]]; then
    ok "$ns/$name ($capacity) - Bound"
  else
    fail "$ns/$name - $status"
    add_issue "PVC $ns/$name is $status"
  fi
done

# ============================================================================
section "6. LONGHORN STORAGE"
# ============================================================================

subsection "Longhorn Volumes"
if kubectl get volumes.longhorn.io -n longhorn-system &>/dev/null; then
  kubectl get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    state=$(echo "$line" | awk '{print $3}')
    robustness=$(echo "$line" | awk '{print $4}')
    size_bytes=$(echo "$line" | awk '{print $6}')
    node=$(echo "$line" | awk '{print $7}')
    size_human=$(numfmt --to=iec "$size_bytes" 2>/dev/null || echo "${size_bytes}B")
    if [[ "$state" == "attached" && "$robustness" == "healthy" ]]; then
      ok "$name ($size_human) on $node - $state/$robustness"
    elif [[ "$state" == "detached" ]]; then
      warn "$name ($size_human) - detached/$robustness"
      add_issue "Longhorn volume $name is detached"
    else
      fail "$name ($size_human) on $node - $state/$robustness"
      add_issue "Longhorn volume $name is $state/$robustness"
    fi
  done
else
  warn "Longhorn CRDs not found"
fi

subsection "Longhorn Nodes"
if kubectl get nodes.longhorn.io -n longhorn-system &>/dev/null; then
  kubectl get nodes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    ready=$(echo "$line" | awk '{print $2}')
    schedulable=$(echo "$line" | awk '{print $4}')
    if [[ "$ready" == "True" && "$schedulable" == "True" ]]; then
      ok "$name - Ready, Schedulable"
    else
      warn "$name - Ready=$ready, Schedulable=$schedulable"
      add_issue "Longhorn node $name: Ready=$ready, Schedulable=$schedulable"
    fi
  done
fi

subsection "Longhorn Snapshots & Recurring Jobs"
if kubectl get recurringjobs.longhorn.io -n longhorn-system &>/dev/null; then
  JOBS=$(kubectl get recurringjobs.longhorn.io -n longhorn-system --no-headers 2>/dev/null || true)
  if [[ -z "$JOBS" ]]; then
    warn "No Longhorn recurring snapshot/backup jobs configured"
    add_issue "No Longhorn recurring jobs found"
  else
    echo "$JOBS" | while IFS= read -r line; do
      ok "$line"
    done
  fi
fi

# ============================================================================
section "7. VELERO BACKUPS"
# ============================================================================

if command -v velero &>/dev/null; then
  subsection "Backup Schedule"
  velero schedule get 2>/dev/null | while IFS= read -r line; do
    info "$line"
  done

  subsection "Recent Backups (last 10)"
  velero backup get --output=json 2>/dev/null | jq -r '.items | sort_by(.metadata.creationTimestamp) | reverse | .[:10][] | "\(.metadata.name) | \(.status.phase) | \(.metadata.creationTimestamp)"' 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | cut -d'|' -f1 | xargs)
    phase=$(echo "$line" | cut -d'|' -f2 | xargs)
    ts=$(echo "$line" | cut -d'|' -f3 | xargs)
    if [[ "$phase" == "Completed" ]]; then
      ok "$name - $phase ($ts)"
    elif [[ "$phase" == "PartiallyFailed" ]]; then
      warn "$name - $phase ($ts)"
      add_issue "Velero backup $name partially failed"
    else
      fail "$name - $phase ($ts)"
      add_issue "Velero backup $name: $phase"
    fi
  done

  subsection "Backup Storage Locations"
  velero backup-location get 2>/dev/null | while IFS= read -r line; do
    info "$line"
  done
elif kubectl get backups.velero.io -n velero &>/dev/null; then
  subsection "Velero Backups (via kubectl)"
  kubectl get backups.velero.io -n velero --no-headers 2>/dev/null | tail -10 | while IFS= read -r line; do
    info "$line"
  done

  subsection "Backup Schedules"
  kubectl get schedules.velero.io -n velero --no-headers 2>/dev/null | while IFS= read -r line; do
    info "$line"
  done

  subsection "Backup Storage Locations"
  kubectl get backupstoragelocations.velero.io -n velero --no-headers 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    phase=$(echo "$line" | awk '{print $2}')
    if [[ "$phase" == "Available" ]]; then
      ok "$name - $phase"
    else
      fail "$name - $phase"
      add_issue "Velero BSL $name is $phase"
    fi
  done
else
  warn "Velero not found"
  add_issue "Velero not installed or not accessible"
fi

# ============================================================================
section "8. ARGOCD"
# ============================================================================

subsection "ArgoCD Applications"
if kubectl get applications.argoproj.io -n argocd &>/dev/null; then
  kubectl get applications.argoproj.io -n argocd --no-headers 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    sync=$(echo "$line" | awk '{print $2}')
    health=$(echo "$line" | awk '{print $3}')
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      ok "$name - $sync/$health"
    elif [[ "$health" == "Degraded" || "$health" == "Missing" ]]; then
      fail "$name - $sync/$health"
      add_issue "ArgoCD app $name is $health"
    else
      warn "$name - $sync/$health"
      add_issue "ArgoCD app $name: sync=$sync health=$health"
    fi
  done
else
  warn "ArgoCD CRDs not found"
fi

# ============================================================================
section "9. CERT-MANAGER & CERTIFICATES"
# ============================================================================

subsection "Certificates"
if kubectl get certificates -A &>/dev/null; then
  kubectl get certificates -A --no-headers 2>/dev/null | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    ready=$(echo "$line" | awk '{print $3}')
    if [[ "$ready" == "True" ]]; then
      ok "$ns/$name - Ready"
    else
      fail "$ns/$name - Not Ready"
      add_issue "Certificate $ns/$name is not ready"
    fi
  done
else
  warn "cert-manager CRDs not found"
fi

subsection "Certificate Expiry"
if kubectl get certificates -A -o json &>/dev/null; then
  kubectl get certificates -A -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.status.notAfter // "unknown")"' 2>/dev/null | while IFS= read -r line; do
    cert=$(echo "$line" | awk '{print $1}')
    expiry=$(echo "$line" | awk '{print $2}')
    if [[ "$expiry" != "unknown" ]]; then
      expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
      if [[ $days_left -lt 7 ]]; then
        fail "$cert expires in $days_left days ($expiry)"
        add_issue "Certificate $cert expires in $days_left days"
      elif [[ $days_left -lt 30 ]]; then
        warn "$cert expires in $days_left days ($expiry)"
      else
        ok "$cert expires in $days_left days"
      fi
    fi
  done
fi

subsection "ClusterIssuers"
kubectl get clusterissuers --no-headers 2>/dev/null | while IFS= read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  ready=$(echo "$line" | awk '{print $2}')
  if [[ "$ready" == "True" ]]; then
    ok "$name - Ready"
  else
    fail "$name - Not Ready"
    add_issue "ClusterIssuer $name is not ready"
  fi
done

# ============================================================================
section "10. SEALED SECRETS"
# ============================================================================

subsection "Sealed Secrets Controller"
SS_POD=$(kubectl get pods -n kube-system -l name=sealed-secrets-controller --no-headers 2>/dev/null || \
         kubectl get pods -A -l app.kubernetes.io/name=sealed-secrets --no-headers 2>/dev/null || true)
if [[ -n "$SS_POD" ]]; then
  ok "Sealed Secrets controller running"
  echo "  $SS_POD"
else
  warn "Sealed Secrets controller not found (may use different labels)"
fi

subsection "SealedSecrets Count by Namespace"
if kubectl get sealedsecrets -A &>/dev/null; then
  kubectl get sealedsecrets -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | while IFS= read -r line; do
    info "$line"
  done
fi

# ============================================================================
section "11. NETWORKING & INGRESS"
# ============================================================================

subsection "Ingress Resources"
kubectl get ingress -A --no-headers 2>/dev/null | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')
  hosts=$(echo "$line" | awk '{print $4}')
  info "$ns/$name -> $hosts"
done

subsection "Services (LoadBalancer & NodePort)"
kubectl get svc -A --no-headers 2>/dev/null | grep -E "LoadBalancer|NodePort" | while IFS= read -r line; do
  ns=$(echo "$line" | awk '{print $1}')
  name=$(echo "$line" | awk '{print $2}')
  type=$(echo "$line" | awk '{print $3}')
  ports=$(echo "$line" | awk '{print $5}')
  info "$ns/$name ($type) - $ports"
done

subsection "Traefik IngressRoutes"
if kubectl get ingressroutes.traefik.io -A &>/dev/null; then
  kubectl get ingressroutes.traefik.io -A --no-headers 2>/dev/null | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    info "$ns/$name"
  done
fi

# ============================================================================
section "12. CRONJOBS & JOBS"
# ============================================================================

subsection "CronJobs"
CRONS=$(kubectl get cronjobs -A --no-headers 2>/dev/null || true)
if [[ -z "$CRONS" ]]; then
  info "No CronJobs found"
else
  echo "$CRONS" | while IFS= read -r line; do
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    schedule=$(echo "$line" | awk '{print $3}')
    last=$(echo "$line" | awk '{print $6}')
    info "$ns/$name - Schedule: $schedule - Last: $last"
  done
fi

subsection "Failed Jobs (last 24h)"
FAILED_JOBS=$(kubectl get jobs -A --no-headers 2>/dev/null | grep -v "1/1" | grep -v "Completed" || true)
if [[ -z "$FAILED_JOBS" ]]; then
  ok "No failed jobs"
else
  echo "$FAILED_JOBS" | while IFS= read -r line; do
    warn "$line"
  done
fi

# ============================================================================
section "13. SECURITY"
# ============================================================================

subsection "Authelia"
AUTH_PODS=$(kubectl get pods -A -l app=authelia --no-headers 2>/dev/null || \
            kubectl get pods -A --no-headers 2>/dev/null | grep authelia || true)
if [[ -n "$AUTH_PODS" ]]; then
  echo "$AUTH_PODS" | while IFS= read -r line; do
    status=$(echo "$line" | awk '{print $4}')
    if [[ "$status" == "Running" ]]; then
      ok "Authelia: $line"
    else
      fail "Authelia: $line"
      add_issue "Authelia pod not running"
    fi
  done
else
  warn "No Authelia pods found"
fi

subsection "Trivy Operator"
if kubectl get vulnerabilityreports -A &>/dev/null; then
  VULN_COUNT=$(kubectl get vulnerabilityreports -A --no-headers 2>/dev/null | wc -l)
  CRITICAL_VULNS=$(kubectl get vulnerabilityreports -A -o json 2>/dev/null | jq '[.items[].report.summary.criticalCount // 0] | add' 2>/dev/null || echo "?")
  HIGH_VULNS=$(kubectl get vulnerabilityreports -A -o json 2>/dev/null | jq '[.items[].report.summary.highCount // 0] | add' 2>/dev/null || echo "?")
  info "$VULN_COUNT vulnerability reports"
  if [[ "$CRITICAL_VULNS" != "?" && "$CRITICAL_VULNS" -gt 0 ]]; then
    fail "Critical vulnerabilities: $CRITICAL_VULNS"
    add_issue "$CRITICAL_VULNS critical vulnerabilities found by Trivy"
  else
    ok "Critical vulnerabilities: ${CRITICAL_VULNS:-0}"
  fi
  if [[ "$HIGH_VULNS" != "?" && "$HIGH_VULNS" -gt 0 ]]; then
    warn "High vulnerabilities: $HIGH_VULNS"
  else
    ok "High vulnerabilities: ${HIGH_VULNS:-0}"
  fi
else
  info "Trivy Operator CRDs not found"
fi

# ============================================================================
section "14. MONITORING STACK"
# ============================================================================

for app in grafana prometheus loki promtail node-exporter; do
  pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep "$app" || true)
  if [[ -n "$pods" ]]; then
    running=$(echo "$pods" | grep -c "Running" || true)
    total=$(echo "$pods" | wc -l)
    if [[ "$running" -eq "$total" ]]; then
      ok "$app: $running/$total running"
    else
      warn "$app: $running/$total running"
      add_issue "$app: only $running/$total pods running"
    fi
  else
    warn "$app: no pods found"
  fi
done

# ============================================================================
section "15. RECENT CLUSTER EVENTS (Warnings)"
# ============================================================================

WARN_EVENTS=$(kubectl get events -A --sort-by='.lastTimestamp' --field-selector type=Warning 2>/dev/null | tail -15 || true)
if [[ -z "$WARN_EVENTS" || "$WARN_EVENTS" == "No resources found" ]]; then
  ok "No recent warning events"
else
  echo "$WARN_EVENTS" | while IFS= read -r line; do
    echo "  $line"
  done
fi

# ============================================================================
section "16. RESOURCE QUOTAS & LIMITS"
# ============================================================================

subsection "Resource Quotas"
RQ=$(kubectl get resourcequotas -A --no-headers 2>/dev/null || true)
if [[ -z "$RQ" ]]; then
  info "No resource quotas defined"
else
  echo "$RQ"
fi

subsection "LimitRanges"
LR=$(kubectl get limitranges -A --no-headers 2>/dev/null || true)
if [[ -z "$LR" ]]; then
  info "No LimitRanges defined"
else
  echo "$LR"
fi

# ============================================================================
section "17. IMAGES & VERSIONS"
# ============================================================================

subsection "Container Images in Use"
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u | while IFS= read -r img; do
  info "$img"
done

# ============================================================================
# SUMMARY
# ============================================================================
section "AUDIT SUMMARY"

TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || true)
TOTAL_PVC=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)
BOUND_PVC=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c "Bound" || true)
TOTAL_DEPLOY=$(kubectl get deployments -A --no-headers 2>/dev/null | wc -l)
TOTAL_NS=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l)

echo ""
info "Nodes:        $(kubectl get nodes --no-headers 2>/dev/null | wc -l)"
info "Namespaces:   $TOTAL_NS"
info "Pods:         $RUNNING_PODS/$TOTAL_PODS running"
info "Deployments:  $TOTAL_DEPLOY"
info "PVCs:         $BOUND_PVC/$TOTAL_PVC bound"
echo ""

if [[ ${#ISSUES[@]} -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}  ✓ NO ISSUES FOUND - Cluster looks healthy!${NC}"
else
  echo -e "${RED}${BOLD}  ✗ ${#ISSUES[@]} ISSUE(S) FOUND:${NC}"
  echo ""
  for i in "${!ISSUES[@]}"; do
    echo -e "  ${RED}$((i+1)). ${ISSUES[$i]}${NC}"
  done
fi

echo ""
echo -e "${CYAN}Audit completed at $(date)${NC}"
