#!/bin/sh
# Collect what the A21s port needs from the phone: its live device tree, memory
# map, storage type, framebuffer, partitions, and a backup of the boot-chain
# partitions. READ-ONLY on the phone.
#   tools/a21s-collect.sh [-s SERIAL] [-b] OUT_DIR
# Run it with the phone booted into a recovery with `adb root` (TWRP/OrangeFox)
# or into rooted Android. -b also copies boot/vbmeta/dtbo (and the Samsung
# calibration partitions that exist) to OUT_DIR/backup/ -- do that FIRST, before
# the first flash. OUT_DIR holds IMEI/calibration data: keep it out of git
# (.gitignore lists a21s-dump/).
set -eu

ADB="adb"
BACKUP=0
while [ $# -gt 0 ]; do
	case "$1" in
	-h|--help) sed -n 2,11p "$0"; exit 0 ;;
	-s) ADB="adb -s ${2:?-s needs a serial}"; shift 2 ;;
	-b) BACKUP=1; shift ;;
	*) break ;;
	esac
done
out=${1:?usage: a21s-collect.sh [-s SERIAL] [-b] OUT_DIR}
command -v adb >/dev/null 2>&1 || { echo "Error: adb not found in PATH" >&2; exit 1; }
$ADB shell 'id -u' 2>/dev/null | tr -d '\r' | grep -qx 0 ||
	{ echo "Error: need root over adb (recovery with adb root, or rooted Android)" >&2; exit 1; }
mkdir -p "$out"

sh_out() { $ADB shell "$2" 2>/dev/null | tr -d '\r' > "$out/$1" || true; }

# 1. The device tree the bootloader handed Linux: every address/IRQ/reserved region.
$ADB pull /sys/firmware/fdt "$out/fdt.dtb" >/dev/null 2>&1 ||
	$ADB exec-out 'cat /sys/firmware/fdt' > "$out/fdt.dtb"
command -v dtc >/dev/null 2>&1 && dtc -I dtb -O dts -o "$out/fdt.dts" "$out/fdt.dtb" 2>/dev/null || true

# 2. Memory map and interrupt/CPU facts
sh_out iomem.txt 'cat /proc/iomem'
sh_out cpuinfo.txt 'cat /proc/cpuinfo'
sh_out interrupts.txt 'cat /proc/interrupts'
sh_out cmdline.txt 'cat /proc/cmdline'
sh_out meminfo.txt 'head -3 /proc/meminfo'
sh_out cntfrq.txt 'dmesg | grep -i -E "arch_timer|cntfrq|Architected"'
sh_out gic.txt 'dmesg | grep -i -E "gic|irq-"'

# 3. Storage: eMMC (mmc_host / mmcblk) or UFS (host/ufs, sd*)?
sh_out storage.txt 'ls -l /sys/class/mmc_host /sys/class/scsi_host /sys/block 2>&1; ls /sys/bus/platform/drivers | grep -i -E "mmc|mshc|ufs|dw"; ls -l /dev/block/by-name 2>&1'
sh_out partitions.txt 'cat /proc/partitions'

# 4. Display / framebuffer the bootloader leaves behind
sh_out fb.txt 'for f in /sys/class/graphics/fb0/*; do [ -f $f ] && echo "$f: $(cat $f 2>/dev/null | head -1)"; done'
sh_out display.txt 'dmesg | grep -i -E "framebuffer|splash|lcd|panel|decon|dsim|cont_splash"'
sh_out reserved.txt 'dmesg | grep -i -E "reserved|cma|carveout"'

# 5. Input, power, USB: which chips (drivers) the touch/keys/PMIC/USB actually are
sh_out input.txt 'cat /proc/bus/input/devices'
sh_out i2c.txt 'ls -l /sys/bus/i2c/devices /sys/bus/spi/devices 2>&1'
sh_out power.txt 'ls /sys/class/power_supply /sys/class/regulator 2>&1 | head -80'
sh_out usb.txt 'ls -l /sys/class/udc /sys/bus/platform/drivers 2>&1 | grep -i -E "udc|dwc|usb|exynos"'
sh_out props.txt 'for p in ro.product.model ro.product.device ro.board.platform ro.hardware ro.boot.hardware ro.build.version.release ro.boot.bootloader ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.warranty_bit ro.boot.vbmeta.device_state ro.build.ab_update ro.boot.dynamic_partitions; do echo "$p=$(getprop $p)"; done'

# 6. Optional backup of the boot chain (needed to recover from a bad flash)
if [ "$BACKUP" = 1 ]; then
	mkdir -p "$out/backup"
	for n in boot vbmeta dtbo recovery efs sec_efs persistent param nvitem nvdata; do
		dev=$($ADB shell "for d in /dev/block/by-name/$n /dev/block/platform/*/by-name/$n; do [ -e \$d ] && readlink -f \$d && break; done" 2>/dev/null | tr -d '\r')
		[ -n "$dev" ] || { echo "skip $n (not present)"; continue; }
		echo "backup $n <- $dev"
		$ADB exec-out "dd if=$dev bs=1048576 2>/dev/null" > "$out/backup/$n.img"
	done
	(cd "$out/backup" && sha256sum *.img > SHA256SUMS 2>/dev/null || true)
fi
echo "done: $out  (do not commit it)"
