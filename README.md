# epson-setup

One-shot installer for a networked **Epson EcoTank M3170** (and similar
driverless Epson multifunctions) on Debian/Ubuntu Linux.

Configures **printing** (IPP Everywhere) and **scanning** (eSCL/AirScan,
including the ADF) — no proprietary Epson packages required.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/xthakila/epson-setup/main/setup.sh | sudo bash
```

or:

```bash
git clone https://github.com/xthakila/epson-setup.git
cd epson-setup
sudo ./setup.sh
```

## Options

```
sudo ./setup.sh                       # auto-discover via mDNS
sudo ./setup.sh --ip 192.168.1.50     # skip mDNS, use this IP
sudo ./setup.sh --queue MyPrinter     # custom CUPS queue name
sudo ./setup.sh --match 'EPSON.*M3170' # change the mDNS name pattern
```

The script is idempotent — safe to re-run.

## What it installs

- **CUPS** + `cups-browsed` + `cups-ipp-utils` (printing)
- **Avahi** (mDNS auto-discovery)
- **SANE** + `sane-airscan` + `libsane1` (scanning; `escl` backend for ADF)
- `simple-scan` GUI, `system-config-printer`, `printer-driver-cups-pdf`

## What it does

1. Installs the packages above.
2. Enables `cups`, `cups-browsed`, `avahi-daemon`.
3. Adds the invoking user to the `lp`, `lpadmin`, `scanner` groups.
4. Discovers the printer over mDNS (or uses `--ip`).
5. Creates a CUPS queue with the driverless **IPP Everywhere** model.
6. Sets it as the default printer if none is configured yet.
7. Verifies the scanner shows up in `scanimage -L`.

## Verifying

```bash
lpstat -p -d                              # printer status
lp /usr/share/cups/data/testprint         # CUPS test page
scanimage -L                              # list scanners
simple-scan                               # GUI scan (run as your user)
```

## Notes

- After a fresh group addition, log out and back in for `lp`/`scanner`
  group membership to take effect.
- **ADF on M3170**: the SANE `escl:` device is more reliable than the
  `airscan:` device — `simple-scan` will let you pick. Make sure the
  side paper-width guides are pushed snug against the paper or the
  printer's sensor will report `ScannerAdfEmpty`.
- Requires the printer and the PC to be on the same L2 network for mDNS
  auto-discovery. Otherwise pass `--ip`.

## Compatibility

Tested on Ubuntu 25.10. Targets any Debian-family distro with apt
(Debian 12+, Ubuntu 22.04+, Mint, Pop!_OS, etc.).

Other driverless Epson EcoTank / WorkForce models that advertise
IPP Everywhere + eSCL over mDNS should also work — adjust `--match`
and `--queue` accordingly.
