# TP-Link AC1300 (Archer T3U Plus) — offline Ubuntu packages

Offline enablement kit for the **TP-Link AC1300 Archer T3U Plus** USB Wi-Fi adapter
(USB ID `2357:0138`, Realtek **RTL8822BU**) on **Ubuntu 24.04**, with no internet
access on the target machine.

The kernel 6.8 `rtw88_8822bu` driver is used — no third-party DKMS driver needed.
The kit supplies the missing RTL8822BU firmware, optional helper `.deb` packages,
diagnostics, and a persistence fix for firmware power-save issues.

## Layout

```
.
├── README.md
└── rtl8822bu-t3u/
    ├── rtl8822bu-t3u-offline-ubuntu24.04.tar.gz   # ready-to-copy release archive
    └── pkg/
        ├── README.md            # full documentation (Chinese)
        ├── install.sh           # one-shot installer (firmware + tools + self-check)
        ├── check.sh             # read-only diagnostics
        ├── fetch-debs.sh        # fetch extra debs on a networked machine
        ├── fix-persistence.sh   # persistent power-save / LPS fix
        ├── firmware/rtw88/rtw8822b_fw.bin
        └── debs/                # iw, wpasupplicant, wireless-tools, regdb
```

## Quick start (offline machine)

```bash
tar xzf rtl8822bu-t3u-offline-ubuntu24.04.tar.gz
cd rtl8822bu-t3u-offline
./check.sh            # diagnostics
sudo ./install.sh     # install firmware, missing tools, reload driver
```

For power-save instability across reboots:

```bash
sudo bash ./fix-persistence.sh
```

See [`rtl8822bu-t3u/pkg/README.md`](rtl8822bu-t3u/pkg/README.md) for the full
guide, troubleshooting table, and verification results.
