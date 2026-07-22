#!/usr/bin/env bash
# set-wake-schedule.sh
#
# Toggles the fleet apt update/suspend cycle between two schedules:
#   home    -> wake Elmore at 3:00 AM MDT
#   europe  -> wake Elmore at 7:00 PM MDT
#
# Run this ON ELMORE. It updates:
#   1. The Wake-on-LAN cron entry on Alabama (via SSH)
#   2. The OpenClaw cron job's trigger time (local)
#   3. Elmore's local fail-safe suspend cron entry (local)
#
# Usage:
#   ./set-wake-schedule.sh home
#   ./set-wake-schedule.sh europe
#   ./set-wake-schedule.sh status

set -euo pipefail

# ---- Fill these in before first use ----
CRON_JOB_ID="708b6580-1713-464b-988f-7cef5a36aa3f"  # nightly-fleet-update (created 2026-07-21)
ELMORE_MAC="a0:ad:9f:cd:9f:f9"           # Elmore eno1
# -----------------------------------------

STATE_FILE="$HOME/.local/state/wake-schedule-mode"
MARKER="# managed-by-set-wake-schedule"

# Home: wake 3:00 AM, task runs 3:10 AM, fail-safe suspend 4:00 AM (all MDT)
HOME_WOL_CRON="0 3 * * *"
HOME_TASK_CRON="10 3 * * *"
HOME_FAILSAFE_CRON="0 4 * * *"

# Europe: wake 7:00 PM MDT, task runs 7:10 PM, fail-safe suspend 8:00 PM
EUROPE_WOL_CRON="0 19 * * *"
EUROPE_TASK_CRON="10 19 * * *"
EUROPE_FAILSAFE_CRON="0 20 * * *"

usage() {
  echo "Usage: $0 {home|europe|status}"
  exit 1
}

[ $# -eq 1 ] || usage
MODE="$1"

show_status() {
  if [ -f "$STATE_FILE" ]; then
    echo "Current mode: $(cat "$STATE_FILE")"
  else
    echo "Current mode: unknown (never set)"
  fi
  echo
  echo "-- Alabama WoL crontab --"
  ssh alabama "crontab -l 2>/dev/null | grep -F '$MARKER' || echo '(none found)'"
  echo
  echo "-- Elmore fail-safe crontab --"
  crontab -l 2>/dev/null | grep -F "$MARKER" || echo "(none found)"
  echo
  echo "-- OpenClaw cron job ($CRON_JOB_ID) --"
  openclaw cron list | grep -A2 "$CRON_JOB_ID" || echo "(job not found — check CRON_JOB_ID in this script)"
}

if [ "$MODE" = "status" ]; then
  show_status
  exit 0
fi

case "$MODE" in
  home)
    WOL_CRON="$HOME_WOL_CRON"
    TASK_CRON="$HOME_TASK_CRON"
    FAILSAFE_CRON="$HOME_FAILSAFE_CRON"
    ;;
  europe)
    WOL_CRON="$EUROPE_WOL_CRON"
    TASK_CRON="$EUROPE_TASK_CRON"
    FAILSAFE_CRON="$EUROPE_FAILSAFE_CRON"
    ;;
  *)
    usage
    ;;
esac

if [ "$CRON_JOB_ID" = "REPLACE_WITH_JOB_ID" ] || [ "$ELMORE_MAC" = "AA:BB:CC:DD:EE:FF" ]; then
  echo "ERROR: Edit this script first and fill in CRON_JOB_ID and ELMORE_MAC at the top." >&2
  exit 1
fi

echo "Switching wake schedule to: $MODE"

echo "-> Updating WoL schedule on Alabama..."
ssh alabama "
  (crontab -l 2>/dev/null | grep -vF '$MARKER'; echo '$WOL_CRON wakeonlan $ELMORE_MAC $MARKER') | crontab -
"

echo "-> Updating OpenClaw cron job ($CRON_JOB_ID)..."
openclaw cron edit "$CRON_JOB_ID" --cron "$TASK_CRON"

echo "-> Updating fail-safe suspend schedule on Elmore..."
(crontab -l 2>/dev/null | grep -vF "$MARKER"; echo "$FAILSAFE_CRON /usr/bin/systemctl suspend $MARKER") | crontab -

mkdir -p "$(dirname "$STATE_FILE")"
echo "$MODE" > "$STATE_FILE"

echo
echo "Done. Now running in '$MODE' mode:"
echo "  WoL wake:        $WOL_CRON  (Alabama)"
echo "  Task trigger:    $TASK_CRON (Elmore, via openclaw cron)"
echo "  Fail-safe sleep: $FAILSAFE_CRON (Elmore)"