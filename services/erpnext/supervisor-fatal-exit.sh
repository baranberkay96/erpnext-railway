#!/bin/bash
# supervisord event listener: on PROCESS_STATE_FATAL, terminate supervisord (PID 1)
# so the container exits and Railway's restart policy brings the whole stack back.
set -u
while true; do
  printf 'READY\n'
  read -r header || exit 0
  len="$(sed -n 's/.*len:\([0-9]*\).*/\1/p' <<<"${header}")"
  payload=""
  [ -n "${len}" ] && [ "${len}" -gt 0 ] && read -r -N "${len}" payload
  echo "[supervisor-fatal-exit] process entered FATAL (${payload}); stopping container" >&2
  kill -TERM 1
  printf 'RESULT 2\nOK'
done
