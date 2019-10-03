// Copyright 2018 the u-root Authors. All rights reserved
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

	.globl kernel_start
	.align 20
kernel_start:
	.incbin "boot/zImage.full"
kernel_end:
	.align 2
	.globl kernel_size
kernel_size:
	.int kernel_end - kernel_start

	.globl dtb_start
	.align 8
dtb_start:
	.incbin "boot/platform.dtb"
dtb_end:
	.align 2
	.globl dtb_size
dtb_size:
	.int dtb_end - dtb_start

	.align 20
	.globl initrd_start
initrd_start:
	.incbin "root.squashfs"
initrd_end:
	.globl initrd_size
	.align 2
initrd_size:
	.int initrd_end - initrd_start
