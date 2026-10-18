#!/usr/bin/env bash
# Run a command in the guest's root debug shell (needs `systemd.debug_shell=/dev/hvc1`
# on the guest kernel command line; see docs/debugging.md). Waits for the
# command to finish, up to WAIT seconds: a busy TCG guest answers slowly.
#
#   scripts/vm-shell.sh 'systemctl --failed'
#   WAIT=120 scripts/vm-shell.sh 'journalctl -b -p err --no-pager'
set -euo pipefail
cd "$(dirname "$0")/.."

cmd=${1:?usage: vm-shell.sh '<command>'}
wait=${WAIT:-60}
tag="vmshell$$"

# The marker is quoted apart in the command text, so only its output matches.
scripts/termux-run.sh <<EOF
coproc S { socat - UNIX-CONNECT:\$HOME/omarchy-vm/shell.sock; }
# Drop anything a previous, slower call left behind.
while IFS= read -r -t 2 _ <&"\${S[0]}"; do :; done
printf '%s\n' 'stty -echo 2>/dev/null; export TERM=dumb SYSTEMD_PAGER= SYSTEMD_COLORS=0' >&"\${S[1]}"
printf '%s\n' $(printf '%q' "$cmd") 'echo "__done""_${tag}__"' >&"\${S[1]}"
end=\$((SECONDS + $wait))
while (( SECONDS < end )) && IFS= read -r -t \$((end - SECONDS)) line <&"\${S[0]}"; do
  line=\${line%\$'\r'}
  line=\${line#sh-+([0-9.])# }
  [[ \$line == *"__done_${tag}__" ]] && { kill \$S_PID; exit 0; }
  [[ -n \$line && \$line != *stty\ -echo* ]] && printf '%s\n' "\$line"
done
kill \$S_PID
echo "(no end marker within ${wait}s; output may be incomplete)" >&2
exit 1
EOF
