// Copyright 2018 the u-root Authors. All rights reserved
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

.globl kernel_start
	.align 12
kernel_start:
	.incbin "boot/zImage.full"
kernel_end:
	.globl kernel_size
	.align 2
kernel_size:
	.int kernel_end - kernel_start

	.globl dtb_start
	.align 12
dtb_start:
	.incbin "boot/platform.dtb.full"
dtb_end:
	.globl dtb_size
	.align 2
dtb_size:
	.int dtb_end - dtb_start

	.align 12
	.globl initrd_start
initrd_start:
	.incbin "initramfs.cpio.gz"
initrd_end:
	.globl initrd_size
	.align 2
initrd_size:
	.int initrd_end - initrd_start
