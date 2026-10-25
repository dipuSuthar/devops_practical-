#!/usr/bin/env bash
# Blue/green deployment helper.  Usage: bash scripts/deploy.sh <plan|deploy|rollback|destroy>
# Requires: terraform (init already done in terraform/envs/$TF_ENV), TF_VAR_domain_name, TF_VAR_releases_bucket.
# For "deploy": VERSION must be set and releases/app-$VERSION.zip must already be in S3.
set -euo pipefail
MODE="${1:?usage: deploy.sh plan|deploy|rollback|destroy}"
TF_ENV="${TF_ENV:-dev}"
cd "$(dirname "$0")/../terraform/envs/$TF_ENV"

other() { if [ "$1" = "blue" ]; then echo green; else echo blue; fi; }

CUR=""; BV=""; GV=""
read_state() {
  CUR=$(terraform output -raw active_color 2>/dev/null || true)
  if [ -n "$CUR" ]; then
    BV=$(terraform output -raw blue_version 2>/dev/null || true)
    GV=$(terraform output -raw green_version 2>/dev/null || true)
  fi
}

# args: active_color blue_version green_version idle_full_capacity
tf_args() { echo -var="active_color=$1" -var="blue_version=$2" -var="green_version=$3" -var="idle_full_capacity=$4"; }
tf_apply() { terraform apply -auto-approve -input=false $(tf_args "$@"); }

smoke() { # args: expected_version
  local expect="$1" u; u=$(terraform output -raw app_url)
  echo "Smoke testing $u (expecting release $expect)"
  for i in $(seq 1 30); do
    if curl -fsS --max-time 10 "$u/health/db" >/dev/null &&
       curl -fsS --max-time 10 "$u/version" | grep -q "\"$expect\""; then
      echo "Smoke test passed: $(curl -s "$u/version")"
      echo "HTTP -> HTTPS redirect: $(curl -s -o /dev/null -w '%{http_code}' "http://${u#https://}/")"
      return 0
    fi
    echo "  not ready yet ($i/30)"; sleep 20
  done
  return 1
}

summary() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    { echo "### $1"; echo "- URL: $(terraform output -raw app_url)"; echo "- Active colour: **$2**"; echo "- Release: \`$3\`"; } >> "$GITHUB_STEP_SUMMARY"
  fi
}

case "$MODE" in
  plan)
    read_state
    if [ -z "$CUR" ]; then CUR=blue; BV="plan-only"; fi
    terraform plan -input=false $(tf_args "$CUR" "$BV" "$GV" false)
    ;;

  deploy)
    : "${VERSION:?VERSION env var is required}"
    read_state
    if [ -z "$CUR" ]; then
      echo "== First deployment: creating infrastructure with blue as active =="
      tf_apply blue "$VERSION" "" false
      smoke "$VERSION" || { echo "First deployment failed its smoke test"; exit 1; }
      summary "First deploy" blue "$VERSION"
    else
      IDLE=$(other "$CUR")
      if [ "$IDLE" = "blue" ]; then NB="$VERSION"; NG="$GV"; else NB="$BV"; NG="$VERSION"; fi
      echo "== Active: $CUR | Idle: $IDLE | New release: $VERSION =="
      echo "== Step 1/3: deploy $VERSION to $IDLE (receives no traffic; waits until healthy) =="
      tf_apply "$CUR" "$NB" "$NG" true
      echo "== Step 2/3: shift 100% of traffic to $IDLE =="
      tf_apply "$IDLE" "$NB" "$NG" false
      echo "== Step 3/3: smoke test =="
      if ! smoke "$VERSION"; then
        echo "Smoke test FAILED -> rolling traffic back to $CUR"
        tf_apply "$CUR" "$NB" "$NG" false
        exit 1
      fi
      summary "Blue/green deploy" "$IDLE" "$VERSION"
    fi
    ;;

  rollback)
    read_state
    [ -n "$CUR" ] || { echo "Nothing deployed yet"; exit 1; }
    PREV=$(other "$CUR")
    if [ "$PREV" = "blue" ]; then PV="$BV"; else PV="$GV"; fi
    [ -n "$PV" ] || { echo "No previous release is deployed on $PREV"; exit 1; }
    echo "== Rolling back: $CUR -> $PREV (release $PV) =="
    tf_apply "$PREV" "$BV" "$GV" false
    smoke "$PV"
    summary "Rollback" "$PREV" "$PV"
    ;;

  destroy)
    terraform destroy -auto-approve -input=false
    ;;

  *) echo "unknown mode: $MODE"; exit 1 ;;
esac
