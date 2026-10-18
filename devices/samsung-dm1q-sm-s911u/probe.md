# samsung SM-S911U (dm1q)

Probed 2026-10-18 with `scripts/probe.sh`.

| | |
|---|---|
| Model | `SM-S911U` |
| Codename | `dm1q` / `dm1qsqw` |
| SoC | `QTI SM8550` (`kalama`) |
| GPU | Qualcomm, Adreno (TM) 740, OpenGL ES 3.2 V@0676.77.1
Failed to write while dumping service SurfaceFlinger: Broken pipe |
| RAM | 6.9 GB |
| Android | 16 (SDK 36), patch 2026-09-05 |
| Build | `BP4A.251205.006.S911USQS8FZI1` |
| Carrier/CSC | `TMB` |
| Kernel | `5.15.189-android13-8-33413713-abS911USQS8FZI1` |
| Bootloader locked | `1` (verified boot: `green`) |
| OEM unlock supported | `not reported` |
| KVM / AVF VMs | `no` / `no` |

## Reachable tiers

- **container**: yes (any arm64 Android 7+)
- **vm**: emulated (TCG, no KVM)
- **native**: blocked (bootloader locked, no OEM unlock)
