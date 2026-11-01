#!/bin/bash
# Build the shim and wrap it in a boot.img.
#
#   PLATFORM=sweet (default)  boot.img v2 that mirrors the stock PixelOS header
#   PLATFORM=a21s             Samsung Galaxy A21s (Exynos 850); see docs/A21S.md
#
# a21s needs (no defaults, because none can be guessed):
#   A21S_FB_BASE         framebuffer phys address, e.g. 0xf0000000
#   A21S_BOOTIMG_ARGS    mkbootimg arguments copied from
#                        `unpack_bootimg --boot_img stock-boot.img --format=mkbootimg`
#                        (header version, base, offsets, pagesize, cmdline, dtb)
# optional:
#   A21S_FB_STRIDE       bytes per framebuffer row if not W*4
#   A21S_SAMSUNG_FOOTER  1 = append the "SEANDROIDENFORCE" trailer Samsung images carry
#   CC / OBJCOPY / NM / READELF  cross tools (default aarch64-linux-gnu-*)
set -euo pipefail
cd "$(dirname "$0")"
PLATFORM=${PLATFORM:-sweet}
PFLAGS=""
CC=${CC:-aarch64-linux-gnu-gcc}
OBJCOPY=${OBJCOPY:-aarch64-linux-gnu-objcopy}
NM=${NM:-aarch64-linux-gnu-nm}
READELF=${READELF:-aarch64-linux-gnu-readelf}
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra"
case "$PLATFORM" in
sweet)
	SRCS="start.S shim.c console.c mmu.c fdt.c loader.c ufs.c"
	OUT=shim-boot.img
	;;
a21s)
	: "${A21S_FB_BASE:?set A21S_FB_BASE (framebuffer phys address, see docs/A21S.md)}"
	: "${A21S_BOOTIMG_ARGS:?set A21S_BOOTIMG_ARGS (mkbootimg args from the stock boot.img)}"
	PFLAGS="-DPLATFORM_A21S -DA21S_FB_BASE=${A21S_FB_BASE}UL"
	[ -z "${A21S_FB_STRIDE:-}" ] || PFLAGS="$PFLAGS -DA21S_FB_STRIDE=${A21S_FB_STRIDE}"
	CFLAGS="$CFLAGS $PFLAGS"
	SRCS="start.S shim.c console.c mmu.c fdt.c loader.c"	# no Qualcomm UFS probe
	OUT=shim-boot-a21s.img
	;;
*)
	echo "error: unknown PLATFORM=$PLATFORM (sweet|a21s)" >&2; exit 1 ;;
esac
mkdir -p out
OBJS=""
for f in $SRCS; do
	$CC $CFLAGS -c $f -o out/${f%.*}.o
	OBJS="$OBJS out/${f%.*}.o"
done
# The image runs wherever ABL puts it with no relocation pass: only the
# header's image_size (start.o, linked at 0) may be an absolute address.
abs=$($READELF -r ${OBJS//out\/start.o/} | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
$CC $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	$OBJS -o out/shim.elf
$OBJCOPY -O binary out/shim.elf out/Image
# ABL copies the file; pad to image_size so .bss/stacks exist as zeroed bytes.
size=$($NM out/shim.elf | awk '$3=="_end"{print strtonum("0x"$1)}')
truncate -s "$size" out/Image
# Ramdisk: an xnu payload (tools/mkpayload.py) if given as $1, else an empty
# newc cpio (ABL dislikes a zero-size ramdisk on some builds) -> diagnostics.
if [ -n "${1:-}" ]; then
	cp "$1" out/ramdisk.bin
else
	(cd out && rm -rf rd && mkdir rd && cd rd && find . | cpio -o -H newc --quiet | gzip -9 > ../ramdisk.bin)
fi
if [ "$PLATFORM" = sweet ]; then
	mkbootimg --header_version 2 --kernel out/Image --ramdisk out/ramdisk.bin \
		--dtb ../dtb/boot_unpacked/dtb --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
		--tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
		--os_version 17.0.0 --os_patch_level 2035-06 \
		--cmdline "console=null" -o out/$OUT
else
	# shellcheck disable=SC2086
	mkbootimg --kernel out/Image --ramdisk out/ramdisk.bin $A21S_BOOTIMG_ARGS -o out/$OUT
	# Samsung's bootloader checks for this trailer on stock images; whether it
	# insists on it for a flashed boot is UNVERIFIED (docs/A21S.md).
	[ "${A21S_SAMSUNG_FOOTER:-0}" != 1 ] || printf 'SEANDROIDENFORCE' >> out/$OUT
fi
# Host render of the console layout.
gcc -O1 -Wall $PFLAGS -o out/host_test console.c host_test.c && ./out/host_test
ls -l out/Image out/$OUT
