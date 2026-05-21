#!/usr/bin/env bash
# epson-setup (Fedora): install + configure a networked Epson EcoTank/WorkForce
# multifunction (default: M3170) on Fedora-family Linux for printing
# AND ADF/platen scanning.
#
# Driverless approach:
#   Print  -> IPP Everywhere (PWG-Raster / URF)
#   Scan   -> eSCL/AirScan via SANE `escl` backend (reliable on M3170 ADF)
#            sane-airscan is also installed as a fallback.
#
# Tested target: Fedora 39+. Should also work on RHEL/Rocky/Alma 9+
# (sane-airscan may require EPEL on RHEL-family).
#
# Usage:
#   sudo ./setup-fedora.sh                       # auto-discover via mDNS
#   sudo ./setup-fedora.sh --ip 192.168.100.106  # skip mDNS, use this IP
#   sudo ./setup-fedora.sh --queue EpsonOffice   # custom CUPS queue name
#   sudo ./setup-fedora.sh --match "EPSON.*M3170" # custom mDNS name pattern
#
# Re-running is safe (idempotent).

set -euo pipefail

DEFAULT_MATCH='EPSON.*M3170'
DEFAULT_QUEUE='EPSON_M3170_Series'

MATCH="$DEFAULT_MATCH"
QUEUE="$DEFAULT_QUEUE"
IP=""
SKIP_TEST=0

usage() {
  sed -n '2,19p' "$0"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ip)        IP="$2"; shift 2 ;;
    --queue)     QUEUE="$2"; shift 2 ;;
    --match)     MATCH="$2"; shift 2 ;;
    --skip-test) SKIP_TEST=1; shift ;;
    -h|--help)   usage 0 ;;
    *) echo "unknown arg: $1" >&2; usage 1 ;;
  esac
done

c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
c_blue()   { printf '\033[34m%s\033[0m\n' "$*"; }
step()     { echo; c_blue "==> $*"; }

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E env MATCH="$MATCH" QUEUE="$QUEUE" IP="$IP" SKIP_TEST="$SKIP_TEST" "$0" "$@"
fi

INVOKING_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
if [ -z "$INVOKING_USER" ] || [ "$INVOKING_USER" = "root" ]; then
  c_yellow "Could not determine non-root invoking user; group additions will be skipped."
fi

# Pick package manager (dnf5 on Fedora 41+, dnf on older, yum on RHEL 7)
if command -v dnf5 >/dev/null 2>&1; then
  PM=dnf5
elif command -v dnf >/dev/null 2>&1; then
  PM=dnf
elif command -v yum >/dev/null 2>&1; then
  PM=yum
else
  c_red "This script targets Fedora/RHEL (dnf/yum not found)."
  exit 1
fi

# -----------------------------------------------------------------
step "Installing packages with $PM"
# -----------------------------------------------------------------
PKGS=(
  cups cups-client cups-filters cups-browsed
  avahi avahi-tools nss-mdns
  sane-backends sane-backends-libs sane-airscan
  simple-scan gscan2pdf
  djvulibre unpaper pdftk
  system-config-printer
  cups-pdf
)

# RHEL/Rocky/Alma need EPEL for sane-airscan
if [ -f /etc/redhat-release ] && ! grep -qi fedora /etc/redhat-release; then
  if ! rpm -q epel-release >/dev/null 2>&1; then
    c_yellow "Enabling EPEL for sane-airscan…"
    "$PM" install -y epel-release || true
  fi
fi

"$PM" install -y "${PKGS[@]}"

# -----------------------------------------------------------------
step "Enabling services"
# -----------------------------------------------------------------
for svc in cups.service cups-browsed.service avahi-daemon.service; do
  systemctl enable --now "$svc" >/dev/null 2>&1 || systemctl enable --now "$svc" || true
done

# -----------------------------------------------------------------
step "Configuring firewalld for mDNS (if active)"
# -----------------------------------------------------------------
if systemctl is-active --quiet firewalld 2>/dev/null; then
  if ! firewall-cmd --query-service=mdns >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=mdns >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    c_green "  enabled mdns service in firewalld"
  else
    echo "  mdns already allowed by firewalld"
  fi
fi

# -----------------------------------------------------------------
step "Adding user '$INVOKING_USER' to printer/scanner groups"
# -----------------------------------------------------------------
if [ -n "$INVOKING_USER" ] && [ "$INVOKING_USER" != "root" ]; then
  for grp in lp scanner wheel; do
    if getent group "$grp" >/dev/null 2>&1; then
      if ! id -nG "$INVOKING_USER" | tr ' ' '\n' | grep -qx "$grp"; then
        usermod -aG "$grp" "$INVOKING_USER"
        c_green "  added to $grp (logout/login needed to take effect)"
      else
        echo "  already in $grp"
      fi
    fi
  done
fi

# -----------------------------------------------------------------
step "Discovering printer on the network"
# -----------------------------------------------------------------
HOST=""
if [ -n "$IP" ]; then
  HOST="$IP"
  c_yellow "Using explicit IP: $HOST"
else
  echo "Looking for printer matching: $MATCH  (mDNS, up to 8s)"
  for attempt in 1 2 3 4; do
    LINE=$(timeout 4 avahi-browse -tr _ipp._tcp 2>/dev/null \
           | awk -v re="$MATCH" '
               /^=/ && tolower($0) ~ tolower(re) { hit=1; next }
               hit && /address = / {
                 gsub(/[\[\]]/, "", $3); print $3; exit
               }')
    if [ -n "$LINE" ]; then
      HOST="$LINE"
      break
    fi
    sleep 1
  done
  if [ -z "$HOST" ]; then
    c_red "Could not auto-discover the printer via mDNS."
    c_yellow "Re-run with --ip <printer-ip>, e.g.:"
    c_yellow "  sudo ./setup-fedora.sh --ip 192.168.1.50"
    exit 2
  fi
  c_green "Found: $HOST"
fi

if ! ipptool -tv "ipp://$HOST:631/ipp/print" /dev/stdin >/dev/null 2>&1 <<<'{ OPERATION Get-Printer-Attributes }'; then
  c_red "Printer IPP endpoint unreachable at ipp://$HOST:631/ipp/print"
  exit 3
fi

# -----------------------------------------------------------------
step "Adding CUPS queue '$QUEUE' (IPP Everywhere driverless)"
# -----------------------------------------------------------------
if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  echo "Queue '$QUEUE' already exists — updating device URI."
  lpadmin -p "$QUEUE" -v "ipp://$HOST:631/ipp/print" -E
else
  lpadmin -p "$QUEUE" -E \
          -v "ipp://$HOST:631/ipp/print" \
          -m everywhere \
          -L "Network ($HOST)" \
          -o printer-is-shared=false
  c_green "Queue created."
fi
cupsenable "$QUEUE" >/dev/null 2>&1 || true
cupsaccept "$QUEUE" >/dev/null 2>&1 || true

# Set as default (cups-pdf install may have hijacked the default slot).
lpadmin -d "$QUEUE"
c_green "Set '$QUEUE' as the default printer."

# -----------------------------------------------------------------
step "Verifying scanner (SANE)"
# -----------------------------------------------------------------
SCAN_OUT=$(scanimage -L 2>/dev/null | grep -Ei 'escl|airscan' || true)
if [ -z "$SCAN_OUT" ]; then
  c_yellow "scanimage -L returned no eSCL/airscan devices yet."
  c_yellow "Avahi may need a moment; re-run 'scanimage -L' in a few seconds."
else
  echo "$SCAN_OUT"
  c_green "Scanner detected."
  echo
  c_yellow "Note: for ADF batch scans on the M3170, prefer the 'escl:' device"
  c_yellow "      (the airscan backend has an I/O bug with M3170 ADF)."
fi

# -----------------------------------------------------------------
step "Summary"
# -----------------------------------------------------------------
echo "  Printer queue : $QUEUE  ->  ipp://$HOST:631/ipp/print"
echo "  Default       : $(lpstat -d 2>/dev/null || echo '-')"
echo
echo "Useful commands:"
echo "  lpstat -p -d                                     # show queues"
echo "  lp -d $QUEUE /usr/share/cups/data/testprint      # CUPS test page"
echo "  scanimage -L                                     # list scanners"
echo "  simple-scan                                      # GUI scan"
echo
if [ "$SKIP_TEST" -eq 0 ]; then
  c_yellow "Tip: run 'simple-scan' as your normal user (not root) to test ADF/platen."
fi
echo
c_green "Done. If you were just added to a group, log out and back in for group changes to apply."
