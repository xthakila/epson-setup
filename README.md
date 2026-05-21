# epson-setup

One-shot installer for a networked **Epson EcoTank M3170** (and similar
driverless Epson multifunctions) on Linux.

Configures **printing** (IPP Everywhere) and **scanning** (eSCL/AirScan,
including the ADF) — no proprietary Epson packages required.

| Distro family | Script |
|---|---|
| Debian / Ubuntu / Mint / Pop!_OS | `setup.sh` |
| Fedora / RHEL / Rocky / Alma     | `setup-fedora.sh` |

## Quick start

**Debian/Ubuntu:**

```bash
curl -fsSL https://raw.githubusercontent.com/xthakila/epson-setup/main/setup.sh | sudo bash
```

**Fedora/RHEL:**

```bash
curl -fsSL https://raw.githubusercontent.com/xthakila/epson-setup/main/setup-fedora.sh | sudo bash
```

or clone:

```bash
git clone https://github.com/xthakila/epson-setup.git
cd epson-setup
sudo ./setup.sh           # Debian/Ubuntu
sudo ./setup-fedora.sh    # Fedora/RHEL
```

## Options

Both scripts accept the same flags:

```
sudo ./setup.sh                          # auto-discover via mDNS
sudo ./setup.sh --ip 192.168.1.50        # skip mDNS, use this IP
sudo ./setup.sh --queue MyPrinter        # custom CUPS queue name
sudo ./setup.sh --match 'EPSON.*M3170'   # change the mDNS name pattern
```

The scripts are idempotent — safe to re-run.

## What gets installed

- **CUPS** + `cups-browsed` (driverless IPP Everywhere printing)
- **Avahi** (mDNS auto-discovery; `nss-mdns` on Fedora)
- **SANE** + `sane-airscan` (scanning; uses `escl` backend for ADF)
- `simple-scan` GUI, `system-config-printer`, `cups-pdf`

## What the scripts do

1. Install the packages above.
2. Enable `cups`, `cups-browsed`, `avahi-daemon`.
3. On Fedora: allow the `mdns` service in firewalld if it's active.
4. Add the invoking user to `lp`, `scanner` (and `lpadmin` on Debian).
5. Discover the printer over mDNS (or use `--ip`).
6. Create a CUPS queue with the driverless **IPP Everywhere** model.
7. Set it as the default printer.
8. Verify the scanner shows up in `scanimage -L`.

## Using the printer and scanner (for everyone)

**Printing**: nothing special — print from any app (LibreOffice, Firefox,
GIMP, etc.) and pick **EPSON_M3170_Series** in the print dialog. It's
already the default after running the setup.

**Scanning**: open **Document Scanner** (the `simple-scan` app) from
your application menu — no terminal needed.

In Document Scanner:

1. Click the ☰ menu → **Preferences**.
2. **Scanner**: pick the `escl:` entry for the EPSON M3170 (more
   reliable than the `airscan:` entry for the ADF).
3. **Document type**: Text / Photo / Color as appropriate.
4. Close Preferences. Place pages **face-up, top-edge in** in the ADF
   (or a page face-down on the platen).
5. Click the dropdown next to the **Scan** button → choose
   **All Pages from Feeder** (ADF) or **Single Page** (platen).
6. Hit **Scan**. When done, **Save As** → PDF, JPEG, PNG.

For multi-page documents, ADF + "All Pages from Feeder" + Save as PDF
gives you a single searchable file.

## Verifying from the terminal (advanced)

```bash
lpstat -p -d                              # printer status
lp /usr/share/cups/data/testprint         # CUPS test page
scanimage -L                              # list scanners
simple-scan                               # launch the GUI from a terminal
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
- On RHEL/Rocky/Alma, `sane-airscan` lives in EPEL; the Fedora script
  enables EPEL automatically if needed.

## Compatibility

- Debian/Ubuntu script: tested on Ubuntu 25.10; works on Debian 12+,
  Ubuntu 22.04+, Mint, Pop!_OS.
- Fedora script: targets Fedora 39+; works on RHEL/Rocky/Alma 9+ (with
  EPEL).

Other driverless Epson EcoTank / WorkForce models that advertise
IPP Everywhere + eSCL over mDNS should also work — adjust `--match`
and `--queue` accordingly.
