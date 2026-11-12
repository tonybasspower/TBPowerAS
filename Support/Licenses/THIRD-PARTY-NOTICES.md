# Third-party references

TBPower AS contains **no third-party code**. The SMC charge-inhibit protocol was
implemented independently, after checking public sources for key names and byte values:

* **batt** by charlie0129 — <https://github.com/charlie0129/batt> (GPL-2.0).
  Used only as a reference for the SMC keys `CHTE`, `CH0B`, `CH0C` and their
  enable/disable byte values (`pkg/smc/charging.go`, `pkg/smc/consts_arm64.go`).
  No code was copied.
* **battery** by actuallymentor — <https://github.com/actuallymentor/battery> (MIT).
  Reference for the CHTE-first order on recent firmware; TBPower AS also detects
  its `battery maintain` process to avoid fighting over the same keys.

The AppleSMC client (`Sources/CSMC/smc.c`) follows the widely known public
`smc.c` IOKit layout (struct sizes and selector numbers).

TBPower AS is not affiliated with or endorsed by these projects or by Apple.
