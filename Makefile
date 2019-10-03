# Copyright 2018 u-root Authors
#
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file

#PLATFORM ?= quanta-f06-leopard-ddr3
PLATFORM ?= supermicro-x11ssh-f

LEB := 65408
CROSS_COMPILE ?= arm-none-eabi-
QEMU ?= qemu-system-arm
# Some useful debug flags:
# - in_asm, show ASM as it's being fed into QEMU
# - unimp, show things that the VM tries to do but isn't implemented in QEMU
# Run "make QEMUDEBUGFLAGS='-d help' sim" for more flags
QEMUDEBUGFLAGS ?= -d guest_errors
QEMUFLAGS ?= -display none \
	-drive file=flash.sim.img,format=raw,if=mtd \
	-chardev socket,id=host,path=host.uart,server,nowait \
	-nic user,hostfwd=udp::6053-:53,hostfwd=tcp::6443-:443,hostfwd=tcp::9370-:9370 \
	${QEMUDEBUGFLAGS}
MAKE_JOBS ?= -j8
ABS_ROOT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))/
# This is used to include garbage in the signing process to test verification
# errors in the integration test. It should not be used for any real builds.
TEST_EXTRA_SIGN ?= /dev/null
GIT_VERSION=$(shell (cd $(ABS_ROOT_DIR); git describe --tags --long --always))

# This is to allow integration tests that build new root filesystems outside
# of the source root
ifeq ($(ABS_ROOT_DIR),$(PWD)/)
ROOT_DIR :=
else
ROOT_DIR := $(ABS_ROOT_DIR)
endif

all: flash.img

include $(ROOT_DIR)platform/$(PLATFORM)/Makefile.inc
include $(ROOT_DIR)platform/$(SOC)/Makefile.inc

.PHONY: sim all linux-menuconfig-% test vars pebble

u-bmc:
	go get
	go build

# Linux tree comes from the OpenBMC branch, not the official kernel.org
LINUX_VERSION	:= f9e04c3
LINUX_DIR	:= linux-$(LINUX_VERSION)
LINUX_TAR	:= linux-$(LINUX_VERSION).tar.gz
LINUX_URL	:= https://github.com/openbmc/linux/tarball/$(LINUX_VERSION)
LINUX_HASH	:= 533e6a400c710eb7d3d0a18a9a46d7deac218af59de21e7b95bdcaef99c90e1d

$(LINUX_TAR):
	wget -O "$@" "$(LINUX_URL)"

$(LINUX_DIR)/.valid: $(LINUX_TAR)
	echo "$(LINUX_HASH)  $<" | sha256sum --check
	mkdir -p "$(LINUX_DIR)"
	tar xf "$<" --strip 1 -C "$(LINUX_DIR)"
	touch "$@"

$(LINUX_DIR)/.patched: $(LINUX_DIR)/.valid
	cd $(LINUX_DIR) ; \
	for patch in ../linux-patches/*.patch ; do \
		echo "=> Applying `basename $$patch`" ; \
		git apply "$$patch" || exit 1 ; \
	done
	touch "$@"

FORCE:

boot/boot.bin: FORCE boot/zImage.full root.squashfs boot/platform.dtb
	make \
		-C platform/$(SOC)/boot \
		PLATFORM=$(PLATFORM) \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		boot.bin \

	ln -sf ../platform/$(SOC)/boot/boot.bin $@

boot/kexec:
	# TODO(bluecmd): https://github.com/u-root/u-root/issues/401
	wget https://github.com/bluecmd/tools/raw/master/arm/kexec -O $@
	echo "cda9f2ded9c068be69f95dea11fdbab013de6c6c785a3d2ab259028378c06653  $@" | \
		sha256sum -c
	chmod 755 boot/kexec

boot/signer/signer: boot/signer/main.go
	go get ./boot/signer/
	go build -o $@ ./boot/signer/

boot/loader/loader: boot/loader/main.go
	go get ./boot/loader/
	GOARM=5 GOARCH=$(ARCH) go build -ldflags="-s -w" -o $@ ./boot/loader/

boot/keys/u-bmc.pub: boot/signer/signer boot/keys/u-bmc.key
	# Run signer to make sure the pub file is created
	echo | boot/signer/signer > /dev/null
	touch boot/keys/u-bmc.pub

module/%.ko: $(shell find $(ROOT_DIR)module -name \*.c -type f) boot/zImage.boot
	$(MAKE) $(MAKE_JOBS) \
		-C "$(LINUX_DIR)" \
		O=build/boot \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		ARCH=$(ARCH) \
		M=$(ABS_ROOT_DIR)/module \
		modules
	$(LINUX_DIR)/build/boot/scripts/sign-file sha256 \
		$(LINUX_DIR)/build/boot/certs/signing_key.pem \
		$(LINUX_DIR)/build/boot/certs/signing_key.x509 \
		$@

boot/loader.cpio.gz: boot/loader/loader boot/keys/u-bmc.pub module/bootlock.ko boot/kexec
	rm -f boot/loader.cpio.gz
	sh -c "cd boot/loader/; echo loader | cpio -H newc -ov -F ../loader.cpio"
	sh -c "cd boot/keys/; echo u-bmc.pub | cpio -H newc -oAv -F ../loader.cpio"
	sh -c "cd module/; echo bootlock.ko | cpio -H newc -oAv -F ../boot/loader.cpio"
	sh -c "cd boot/; echo kexec | cpio -H newc -oAv -F loader.cpio"
	gzip boot/loader.cpio

# TODO(bluecmd): Change to ECDSA now when u-boot is gone
boot/keys/u-bmc.key:
	mkdir -p boot/keys/
	chmod 700 boot/keys/
	openssl genrsa -out $@ 2048

# Rebuild the Linux config from the one in the platform directory.
# If you change $(SOC) it is probably best to blow away the Linux directory
$(LINUX_DIR)/build/%/.config: platform/$(SOC)/linux.config.% $(LINUX_DIR)/.patched
	@mkdir -p "$(dir $@)"
	cp "$<" "$@"
	$(MAKE) \
		-C "$(LINUX_DIR)" \
		O="../$(dir $@)" \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		ARCH=$(ARCH) \
		olddefconfig

boot/zImage.full: $(LINUX_DIR)/build/full/.config
	$(MAKE) $(MAKE_JOBS) \
		-C "$(LINUX_DIR)" \
		O="../$(dir $<)" \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		ARCH=$(ARCH) \
		all
	cp "$(dir $<)arch/$(ARCH)/boot/zImage" "$@"


# Don't delete the .config files
.PRECIOUS: $(LINUX_DIR)/build/full/.config
.PRECIOUS: $(LINUX_DIR)/build/boot/.config

# Interactively edit a Linux config and save it back to the config
linux-menuconfig.%: $(LINUX_DIR)/build/%/.config
	$(MAKE) $(MAKE_JOBS) \
		-C "$(LINUX_DIR)" \
		O="../$(dir $<)" \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		ARCH=$(ARCH) \
		menuconfig
	$(MAKE) linux-saveconfig$(suffix $@)
	rm -f $<.old

# After editing the real .config file, run `make linux-saveconfig.full` to store the
# default (stripped down) configuration file back into the source tree
linux-saveconfig.%: $(LINUX_DIR)/build/%/.config
	$(MAKE) $(MAKE_JOBS) \
		-C "$(LINUX_DIR)" \
		O="../$(dir $<)" \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		ARCH=$(ARCH) \
		savedefconfig
	mv "$(dir $<)defconfig" "platform/$(SOC)/linux.config$(suffix $@)"

integration/bzImage: integration/linux.config
	$(MAKE) $(MAKE_JOBS) \
		-C $(LINUX_DIR) O=build/$@/ \
		KCONFIG_CONFIG="$(ABS_ROOT_DIR)$<"
	rm -f $<.old
	cp $(LINUX_DIR)/build/$@/arch/x86/boot/bzImage $@

linux-integration-menuconfig: integration/linux.config
	$(MAKE) $(MAKE_JOBS) \
		-C $(LINUX_DIR)/ O=build/$@/ \
		KCONFIG_CONFIG="$(ABS_ROOT_DIR)$<" \
		menuconfig
	rm -f $<.old

boot/platform.dtb: platform/$(PLATFORM)/platform.dts
	cpp \
		-nostdinc \
		-I $(LINUX_DIR)/arch/$(ARCH)/boot/dts/ \
		-I $(LINUX_DIR)/include \
		-I platform/ \
		-I platform/$(PLATFORM)/boot/ \
		-I boot/ \
		-undef \
		-x assembler-with-cpp \
		$< \
	| dtc -O dtb -o $@ -

root.squashfs: initramfs.cpio $(ROOT_DIR)boot/signer/signer $(ROOT_DIR)boot/platform.dtb $(ROOT_DIR)proto/system.textpb.default boot/keys/u-bmc.pub
	rm -fr root/
	mkdir -p root/root root/etc root/boot
	# TOOD(bluecmd): Move to u-bmc system startup
	echo "nameserver 2001:4860:4860::8888" > root/etc/resolv.conf
	echo "nameserver 2606:4700:4700::1111" >> root/etc/resolv.conf
	echo "nameserver 8.8.8.8" >> root/etc/resolv.conf
	echo "::1 localhost" >> root/etc/hosts
	#cp -v $(ROOT_DIR)boot/zImage.full root/boot/zImage-$(GIT_VERSION)
	#cat $(ROOT_DIR)boot/zImage.full | $(ROOT_DIR)boot/signer/signer > root/boot/zImage-$(GIT_VERSION).gpg
	#cp -v $(ROOT_DIR)boot/platform.dtb.full root/boot/platform-$(GIT_VERSION).dtb
	#cat $(ROOT_DIR)boot/platform.dtb.full | $(ROOT_DIR)boot/signer/signer > root/boot/platform-$(GIT_VERSION).dtb.gpg
	#ln -sf zImage-$(GIT_VERSION) root/boot/zImage
	#ln -sf zImage-$(GIT_VERSION).gpg root/boot/zImage.gpg
	#ln -sf platform-$(GIT_VERSION).dtb root/boot/platform.dtb
	#ln -sf platform-$(GIT_VERSION).dtb.gpg root/boot/platform.dtb.gpg
	cp -v $(ROOT_DIR)boot/keys/u-bmc.pub root/etc/
	ln -sf bbin/bb.gpg root/init.gpg
	mkdir root/config
	cp $(ROOT_DIR)proto/system.textpb.default root/config/system.textpb
	# Rewrite the symlink to a non-absolute to allow non-chrooted following.
	# This is a workaround for the fact that the loader cannot chroot currently.
	ln -sf bbin/bb root/init
	fakeroot sh -c "(cd root/; cpio -idv < ../$(<)) && \
		cat root/bbin/bb $(TEST_EXTRA_SIGN) | \
			$(ROOT_DIR)boot/signer/signer > root/bbin/bb.gpg && \
		mksquashfs root root.squashfs -all-root -noappend -comp zstd"

flash.sim.img: flash.img
	( cat $^ ; perl -e 'print chr(0xFF)x1024 while 1' ) \
		| dd bs=1M count=32 iflag=fullblock > $@

initramfs.cpio: u-bmc ssh_keys.pub config/config.go $(shell find $(ROOT_DIR)cmd $(ROOT_DIR)platform/$(PLATFORM) $(ROOT_DIR)pkg $(ROOT_DIR)proto -name \*.go -type f)
	go generate ./config/
	GOARM=5 GOARCH=$(ARCH) ./u-bmc -o "$@.tmp" -p "$(PLATFORM)"
	mv "$@.tmp" "$@"

initramfs.cpio.gz: initramfs.cpio
	gzip -9 < "$<" > "$@"

test:
	go test $(TESTFLAGS) \
		$(shell find */ -name \*.go | grep -v vendor | cut -f -1 -d '/' | sort -u | xargs -n1 -I{} echo ./{}/... | xargs)

get:
	go get -t $(GETFLAGS) \
		$(shell find */ -name \*.go | grep -v vendor | cut -f -1 -d '/' | sort -u | xargs -n1 -I{} echo ./{}/... | xargs)

vars:
	$(foreach var,$(.VARIABLES),$(info $(var)=$($(var))))

clean:
	\rm -f initramfs.cpio* u-root \
	 flash.img flash.sim.img \
	 boot/zImage* boot/platform.dtb* \
	 boot/loader/loader boot/signer/signer boot/loader.cpio.gz \
	 module/*.o module/*.mod.c module/*.ko module/.*.cmd module/modules.order \
	 module/Module.symvers config/ssh_keys.go config/version.go
	\rm -fr root/ boot/modules/ module/.tmp_versions/ boot/out

pebble:
	go run github.com/letsencrypt/pebble/cmd/pebble \
		-dnsserver 127.0.0.1:6053 \
		-config config/sim-pebble.json

run-ovmf:
	qemu-system-x86_64 -bios $(ROOT_DIR)integration/ovmf.rom \
		-display none \
		-chardev socket,id=host,path=host.uart \
		-serial chardev:host \
		-net none
