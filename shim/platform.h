/*
 * Per-device constants for the shim. Default is the Redmi Note 10 Pro (sweet,
 * SM7150). Build with -DPLATFORM_A21S for the Samsung Galaxy A21s (Exynos 850).
 *
 * Every A21S value is tagged:
 *   [mainline]   from the upstream Linux exynos850.dtsi (SoC-level, but the
 *                phone's vendor DT may differ; confirm with tools/a21s-collect.sh)
 *   [spec]       from the published phone specification
 *   [UNVERIFIED] a guess; must be replaced with a value read off the device
 * Values that cannot be guessed at all are #error until given on the command
 * line, so a build never silently runs with an invented address.
 */
#pragma once

#if defined(PLATFORM_A21S)

#define PLAT_NAME		"a21s"
#define PLAT_GIC_V3		0		/* [mainline] arm,gic-400 = GICv2 */
#define PLAT_QCOM_RESTART	0		/* PSCI SYSTEM_RESET only */
#define PLAT_HAS_UFS_PROBE	0		/* storage is not Qualcomm UFS */
#define NR_CPUS			8		/* [mainline] 8x Cortex-A55, MPIDR 0-3, 0x100-0x103 */

#define GICD_BASE		0x12a01000UL	/* [mainline] */
#define GICC_BASE		0x12a02000UL	/* [mainline] */
#define VTIMER_INTID		27		/* [mainline] PPI 11 */
#define PTIMER_INTID		30		/* [mainline] PPI 14 */
#define SGI_INTID		1
#define TIMEBASE_HZ		26000000UL	/* [UNVERIFIED] shim reads CNTFRQ at runtime anyway */

#ifndef A21S_FB_BASE
#error "A21S_FB_BASE: framebuffer physical address the Samsung bootloader leaves (see docs/A21S.md)"
#endif
#define FB_BASE			A21S_FB_BASE
#define FB_W			720		/* [spec] 6.5" 720x1600 */
#define FB_H			1600
#ifndef A21S_FB_STRIDE
#define A21S_FB_STRIDE		(FB_W * 4)	/* [UNVERIFIED] a8r8g8b8, no row padding */
#endif
#define FB_STRIDE		A21S_FB_STRIDE

#else /* sweet */

#define PLAT_NAME		"sweet"
#define PLAT_GIC_V3		1
#define PLAT_QCOM_RESTART	1
#define PLAT_HAS_UFS_PROBE	1
#define NR_CPUS			8

#define IMEM_RESTART_REASON	0x146aa65cUL	/* qcom,msm-imem restart_reason@65c */
#define RESTART_BOOTLOADER	0x77665500U
#define PSHOLD			0x0c264000UL

#define GICD_BASE		0x17a00000UL
#define GICR_BASE		0x17a60000UL
#define GICR_SIZE		0x100000UL
#define VTIMER_INTID		19		/* DT: <GIC_PPI 3 ...>, not the usual 27 */
#define PTIMER_INTID		18		/* DT: <GIC_PPI 2 ...> */
#define SGI_INTID		1
#define TIMEBASE_HZ		19200000UL

#define FB_BASE			0x9c000000UL	/* reserved-memory cont_splash_region */
#define FB_W			1080
#define FB_H			2400
#define FB_STRIDE		(FB_W * 4)	/* a8r8g8b8, matches mainline simplefb */

#endif

#define FB_PHYS			FB_BASE
