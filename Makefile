SHELL = /bin/bash
JOBS=2

LINUX_VER=5.10.22
# LINUX_VER=5.4.87
LINUX_VER_MAJOR=${shell echo ${LINUX_VER} | cut -d '.' -f1,2}
KBUILD_BUILD_USER=r1cebank
KBUILD_BUILD_HOST=diva-eng
LOCALVERSION=-0
UBOOT_VER=2021.01
BUSYBOX_VER=1.33.0
ARMORYCTL_VER=1.1
APT_GPG_KEY=CEADE0CF01939B21

MEGA = 1048576
SECTOR_SIZE = 512
# The seperate boot partition is used for LUKS booted rootfs in MB
BOOT_PARTITION_START_MEGS=5
BOOT_PARTITION_SIZE_MEGS=128
BOOT_PARTITION_END_MEGS=$(shell echo $$(( $(BOOT_PARTITION_START_MEGS) + $(BOOT_PARTITION_SIZE_MEGS) )) )
# The start of the partition
ROOT_PARTITION_OFFSET=$(shell echo $$(( ($(BOOT_PARTITION_SIZE_MEGS) + $(BOOT_PARTITION_START_MEGS)) * $(MEGA) )))
# The starting of the boot partition, in multiples of 1048576 (1MB)
BOOT_PARTITION_OFFSET=$(shell echo $$(( $(BOOT_PARTITION_START_MEGS) * $(MEGA) )) )
# armory-boot only option
BOOT_CONSOLE ?= on
# armory-boot or u-boot (secure-boot only supports armory-boot)
BOOTLOADER=armory-boot

IMAGE_SIZE=3500

ARMORY_BOOT_REPO=https://github.com/r1cebank/armory-boot
USBARMORY_GIT=https://github.com/r1cebank/usbarmory
USBARMORY_REPO=https://raw.githubusercontent.com/r1cebank/usbarmory/master
ARMORYCTL_REPO=https://github.com/f-secure-foundry/armoryctl
MXC_SCC2_REPO=https://github.com/f-secure-foundry/mxc-scc2
MXS_DCP_REPO=https://github.com/f-secure-foundry/mxs-dcp
CAAM_KEYBLOB_REPO=https://github.com/f-secure-foundry/caam-keyblob
IMG_VERSION=${BOOT_PARSED}-debian_buster-base_image-$(shell /bin/date -u "+%Y%m%d")
LOSETUP_DEV=$(shell /sbin/losetup -f)
LOOP_DEV=$(shell /usr/bin/basename $(LOSETUP_DEV))

.DEFAULT_GOAL := release

SIGNED ?= off
BOOT_PRIVATE_KEY ?= /opt/pki-keys/armory-boot.sec
BOOT_PUBLIC_KEY ?= undefined
HAB_KEYS ?= /opt/pki-keys
LUKS=off

# tuned to provide reasonable startup time on usbarmory
# do not change unless you know what they do
# https://man7.org/linux/man-pages/man8/cryptsetup.8.html

# Avoid PBKDF benchmark and set time cost (iterations)
# directly.  It can be used for LUKS/LUKS2 device only.
LUKS_PBKDF_TIME_COST=4
# Set the memory cost for PBKDF (for Argon2i/id the number
# represents kilobytes).  Note that it is maximal value,
# PBKDF benchmark or available physical memory can decrease
# it.  This option is not available for PBKDF2.
LUKS_PBKDF_MEMORY=23804
# Set the parallel cost for PBKDF (number of threads, up to
# 4).  Note that it is maximal value, it is decreased
# automatically if CPU online count is lower.  This option
# is not available for PBKDF2.
LUKS_PBKDF_PARALLEL=1

ROOTFS_MAPPER_NAME=rootfs
RANDOM_PASSWORD=$(shell /usr/bin/openssl rand -hex 20)
GENERATE_PASSWORD=$(eval LUKS_PASSWORD=$(RANDOM_PASSWORD))

BOOT ?= uSD
BOOT_PARSED=$(shell echo "${BOOT}" | tr '[:upper:]' '[:lower:]')

SD_DEV=mmcblk0
MMC_DEV=mmcblk1
ROOTFS_DEV=$(shell [ ${BOOT} = uSD ] && echo ${SD_DEV} || ${MMC_DEV})

check_params:
ifeq ($(strip $(LUKS_PASSWORD)),)
	echo "Generating LUKS keys"
	$(GENERATE_PASSWORD)
endif
	@if test "${SIGNED}" != "on" && test "${SIGNED}" != "off"; then \
		echo "invalid signed setting, can be on or off"; \
	fi
	@if test "${SIGNED}" = "on"; then \
		if test ${BOOTLOADER} != "armory-boot"; then \
			echo "secure boot is only supported with armory-boot"; \
			exit 1; \
		fi; \
		if test "${BOOT_PRIVATE_KEY}" = ""; then \
			echo "please provide location of the armory-boot private key location: BOOT_PRIVATE_KEY"; \
			exit 1; \
		fi; \
		if test "${HAB_KEYS}" = ""; then \
			echo "please provide location of the HAB keys: HAB_KEYS"; \
			exit 1; \
		fi; \
		if test "${BOOT_PUBLIC_KEY}" = "undefined"; then \
			echo "please provide of the armory-boot public key string: BOOT_PUBLIC_KEY"; \
			exit 1; \
		fi; \
	fi
	@if test "${BOOT}" != "uSD" && test "${BOOT}" != eMMC; then \
			echo "invalid target, mark-two BOOT options are: uSD, eMMC"; \
			exit 1; \
		elif test "${IMX}" != "imx6ul" && test "${IMX}" != "imx6ulz"; then \
			echo "invalid target, mark-two IMX options are: imx6ul, imx6ulz"; \
			exit 1; \
	fi
	@if test "${LUKS}" != "off" && test "${LUKS}" != "on"; then \
		echo "invalid luks setting, options are: on, off"; \
		exit 1; \
	fi
	@echo "target: USB armory IMX=${IMX} BOOT=${BOOT}"

define copy_to_bootfs
	sudo cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dtb bootfs/${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb
	sudo cp -r linux-${LINUX_VER}/arch/arm/boot/zImage bootfs/zImage-${LINUX_VER}${LOCALVERSION}-usbarmory
	sudo cp -r linux-${LINUX_VER}/.config bootfs/config-${LINUX_VER}${LOCALVERSION}-usbarmory
	sudo cp -r linux-${LINUX_VER}/System.map bootfs/System.map-${LINUX_VER}${LOCALVERSION}-usbarmory
	@if test "${BOOTLOADER}" = "armory-boot"; then \
		sudo cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dtb bootfs/${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb; \
		sudo cp -r linux-${LINUX_VER}/arch/arm/boot/zImage bootfs/zImage-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		sudo cp -r linux-${LINUX_VER}/.config bootfs/config-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		sudo cp -r linux-${LINUX_VER}/System.map bootfs/System.map-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		sudo cp -r armory-boot.conf.tmpl bootfs/boot/armory-boot.conf; \
		sed -i 's/ZIMAGE_HASH/$(shell sha256sum /opt/armory/linux-${LINUX_VER}/arch/arm/boot/zImage | cut -d " " -f 1)/' bootfs/boot/armory-boot.conf; \
		sed -i 's/DTB_HASH/$(shell sha256sum /opt/armory/linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dtb | cut -d " " -f 1)/' bootfs/boot/armory-boot.conf; \
		sed -i 's/ZIMAGE/zImage-${LINUX_VER}${LOCALVERSION}-usbarmory/' bootfs/boot/armory-boot.conf; \
		sed -i 's/DTB/${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb/' bootfs/boot/armory-boot.conf; \
		if test "${SIGNED}" = "on"; then \
			echo "${BOOT_PRIVATE_KEY_PASSWORD}"; \
			signify-openbsd -S -s ${BOOT_PRIVATE_KEY} -m bootfs/boot/armory-boot.conf -x bootfs/boot/armory-boot.conf.sig; \
		fi; \
		cd bootfs; \
			ln -sf zImage-${LINUX_VER}${LOCALVERSION}-usbarmory zImage; \
			ln -sf ${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb ${IMX}-usbarmory.dtb; \
			ln -sf ${IMX}-usbarmory.dtb imx6ull-usbarmory.dtb; \
	else \
		sudo cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dtb bootfs/boot/${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb; \
		sudo cp -r linux-${LINUX_VER}/arch/arm/boot/zImage bootfs/boot/zImage-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		sudo cp -r linux-${LINUX_VER}/.config bootfs/boot/config-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		sudo cp -r linux-${LINUX_VER}/System.map bootfs/boot/System.map-${LINUX_VER}${LOCALVERSION}-usbarmory; \
		cd bootfs/boot ; ln -sf zImage-${LINUX_VER}${LOCALVERSION}-usbarmory zImage; \
		cd bootfs/boot ; ln -sf ${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb ${IMX}-usbarmory.dtb; \
		cd bootfs/boot ; ln -sf ${IMX}-usbarmory.dtb imx6ull-usbarmory.dtb; \
	fi
endef

#### armory-boot ####
armory-boot-master.zip:
	wget ${ARMORY_BOOT_REPO}/archive/master.zip -O armory-boot-master.zip
armory-boot-master: armory-boot-master.zip
	unzip -o armory-boot-master.zip
armory-boot.imx: armory-boot-master
	cd armory-boot-master && make BUILD_USER=${KBUILD_BUILD_USER} BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx BOOT=${BOOT} CONSOLE=${BOOT_CONSOLE} START=${BOOT_PARTITION_OFFSET}
armory-boot-signed.imx: armory-boot-master
	cd armory-boot-master && make BUILD_USER=${KBUILD_BUILD_USER} BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- imx_signed BOOT=${BOOT} CONSOLE=${BOOT_CONSOLE} START=${BOOT_PARTITION_OFFSET} PUBLIC_KEY=${BOOT_PUBLIC_KEY} HAB_KEYS=${HAB_KEYS}

#### u-boot ####

u-boot-${UBOOT_VER}.tar.bz2:
	wget ftp://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VER}.tar.bz2 -O u-boot-${UBOOT_VER}.tar.bz2
	wget ftp://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VER}.tar.bz2.sig -O u-boot-${UBOOT_VER}.tar.bz2.sig

u-boot-${UBOOT_VER}/u-boot.bin: check_params u-boot-${UBOOT_VER}.tar.bz2
	gpg --verify u-boot-${UBOOT_VER}.tar.bz2.sig
	tar xfm u-boot-${UBOOT_VER}.tar.bz2
	cd u-boot-${UBOOT_VER} && make distclean
	cd u-boot-${UBOOT_VER} && \
		wget ${USBARMORY_REPO}/software/u-boot/0001-ARM-mx6-add-support-for-USB-armory-Mk-II-board.patch && \
		patch -p1 < 0001-ARM-mx6-add-support-for-USB-armory-Mk-II-board.patch && \
		make usbarmory-mark-two_defconfig
	@if test "${BOOT}" = "eMMC"; then \
		cd u-boot-${UBOOT_VER} && \
			sed -i -e 's/CONFIG_SYS_BOOT_DEV_MICROSD=y/# CONFIG_SYS_BOOT_DEV_MICROSD is not set/' .config; \
			sed -i -e 's/# CONFIG_SYS_BOOT_DEV_EMMC is not set/CONFIG_SYS_BOOT_DEV_EMMC=y/' .config; \
	fi
	cd u-boot-${UBOOT_VER} && CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm make -j${JOBS}

usbarmory-boot-${IMG_VERSION}.img: linux-${LINUX_VER}/arch/arm/boot/zImage
	truncate -s ${BOOT_PARTITION_SIZE_MEGS}MiB usbarmory-boot-${IMG_VERSION}.img
	# setup partition type
	sudo /sbin/parted usbarmory-boot-${IMG_VERSION}.img --script mklabel msdos
	# setup boot partition
	sudo /sbin/parted usbarmory-boot-${IMG_VERSION}.img --script mkpart primary ext4 0% 100%
	sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-boot-${IMG_VERSION}.img
	sudo /sbin/mkfs.ext4 -F $(LOSETUP_DEV)
	sudo /sbin/losetup -d $(LOSETUP_DEV)
	# Mount bootfs
	mkdir -p bootfs
	sudo mount -o loop -t ext4 usbarmory-boot-${IMG_VERSION}.img bootfs/
	sudo mkdir -p bootfs/boot
	# copy all the boot partition files
	$(call copy_to_bootfs)
	sudo umount bootfs

#### debian ####
DEBIAN_DEPS := check_params
DEBIAN_DEPS += armoryctl_${ARMORYCTL_VER}_armhf.deb
DEBIAN_DEPS += linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
DEBIAN_DEPS += linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
usbarmory-${IMG_VERSION}.img: $(DEBIAN_DEPS)
	truncate -s ${IMAGE_SIZE}MiB usbarmory-${IMG_VERSION}.img
	# setup partition type
	sudo /sbin/parted usbarmory-${IMG_VERSION}.img --script mklabel msdos
	# setup boot partition
	sudo /sbin/parted usbarmory-${IMG_VERSION}.img --script mkpart primary ext4 ${BOOT_PARTITION_START_MEGS}MiB ${BOOT_PARTITION_END_MEGS}MiB
	# setup rootfs partition in image
	sudo /sbin/parted usbarmory-${IMG_VERSION}.img --script mkpart primary ext4 ${BOOT_PARTITION_END_MEGS}MiB 100%
	sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.img -o ${BOOT_PARTITION_OFFSET} --sizelimit ${BOOT_PARTITION_SIZE_MEGS}MiB
	sudo /sbin/mkfs.ext4 -F $(LOSETUP_DEV)
	sudo /sbin/losetup -d $(LOSETUP_DEV)
	# make filesystem on the rootfs, luks or ext4
	@if test "${LUKS}" = "off"; then \
		sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.img -o ${ROOT_PARTITION_OFFSET} --sizelimit ${IMAGE_SIZE}MiB; \
		sudo /sbin/mkfs.ext4 -F $(LOSETUP_DEV); \
		sudo /sbin/losetup -d $(LOSETUP_DEV); \
	else \
		sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.img -o ${ROOT_PARTITION_OFFSET} --sizelimit ${IMAGE_SIZE}MiB; \
		sudo /sbin/losetup -d $(LOSETUP_DEV); \
		sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.img; \
		sudo /usr/sbin/kpartx -a $(LOSETUP_DEV); \
		echo -e "Creating luks partition with password: ${LUKS_PASSWORD}"; \
		printf "${LUKS_PASSWORD}" | cryptsetup -y --cipher aes-xts-plain64 --pbkdf-force-iterations ${LUKS_PBKDF_TIME_COST} --pbkdf-memory ${LUKS_PBKDF_MEMORY} --pbkdf-parallel ${LUKS_PBKDF_PARALLEL} luksFormat /dev/mapper/${LOOP_DEV}p2 -; \
		printf "${LUKS_PASSWORD}" | cryptsetup luksOpen /dev/mapper/${LOOP_DEV}p2 ${ROOTFS_MAPPER_NAME} -d -; \
		sudo /sbin/mkfs.ext4 -F /dev/mapper/${ROOTFS_MAPPER_NAME}; \
		cryptsetup luksClose /dev/mapper/${ROOTFS_MAPPER_NAME}; \
		sudo /usr/sbin/kpartx -d $(LOSETUP_DEV); \
		sudo /sbin/losetup -d $(LOSETUP_DEV); \
	fi
	# Mount bootfs
	mkdir -p bootfs
	sudo mount -o loop,offset=${BOOT_PARTITION_OFFSET} -t ext4 usbarmory-${IMG_VERSION}.img bootfs/
	sudo mkdir -p bootfs/boot
	# copy all the boot partition files
	$(call copy_to_bootfs)
	sudo umount bootfs
	# Mount rootfs
	mkdir -p rootfs
	@if test "${LUKS}" = "off"; then \
		sudo mount -o loop,offset=${ROOT_PARTITION_OFFSET} -t ext4 usbarmory-${IMG_VERSION}.img rootfs/; \
	else \
		sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.img; \
		sudo /usr/sbin/kpartx -a $(LOSETUP_DEV); \
		printf ${LUKS_PASSWORD} | cryptsetup luksOpen /dev/mapper/${LOOP_DEV}p2 ${ROOTFS_MAPPER_NAME} -d -; \
		sudo mount /dev/mapper/${ROOTFS_MAPPER_NAME} rootfs/; \
	fi
	sudo update-binfmts --enable qemu-arm
	sudo qemu-debootstrap \
		--include=ssh,sudo,ntpdate,fake-hwclock,openssl,vim,nano,cryptsetup,lvm2,locales,less,cpufrequtils,isc-dhcp-server,haveged,rng-tools,whois,iw,wpasupplicant,dbus,apt-transport-https,dirmngr,ca-certificates,u-boot-tools,mmc-utils,gnupg,libpam-systemd \
		--arch=armhf buster rootfs http://ftp.debian.org/debian/
	sudo install -m 755 -o root -g root conf/rc.local rootfs/etc/rc.local
	sudo install -m 644 -o root -g root conf/sources.list rootfs/etc/apt/sources.list
	sudo install -m 644 -o root -g root conf/dhcpd.conf rootfs/etc/dhcp/dhcpd.conf
	sudo install -m 644 -o root -g root conf/usbarmory.conf rootfs/etc/modprobe.d/usbarmory.conf
	sudo sed -i -e 's/INTERFACESv4=""/INTERFACESv4="usb0"/' rootfs/etc/default/isc-dhcp-server
	echo "tmpfs /tmp tmpfs defaults 0 0" | sudo tee rootfs/etc/fstab
	echo "/dev/${ROOTFS_DEV}p1 /boot ext4 defaults 0 2" | sudo tee -a rootfs/etc/fstab
	echo -e "\nUseDNS no" | sudo tee -a rootfs/etc/ssh/sshd_config
	echo "nameserver 8.8.8.8" | sudo tee rootfs/etc/resolv.conf
	sudo chroot rootfs systemctl mask getty-static.service
	sudo chroot rootfs systemctl mask display-manager.service
	sudo chroot rootfs systemctl mask hwclock-save.service
	sudo chroot rootfs systemctl mask haveged.service
	sudo wget https://f-secure-foundry.github.io/keys/gpg-andrej.asc -O rootfs/tmp/gpg-andrej.asc
	sudo wget https://f-secure-foundry.github.io/keys/gpg-andrea.asc -O rootfs/tmp/gpg-andrea.asc
	sudo chroot rootfs apt-key add /tmp/gpg-andrej.asc
	sudo chroot rootfs apt-key add /tmp/gpg-andrea.asc
	echo "ledtrig_heartbeat" | sudo tee -a rootfs/etc/modules
	echo "ci_hdrc_imx" | sudo tee -a rootfs/etc/modules
	echo "g_ether" | sudo tee -a rootfs/etc/modules
	echo "i2c-dev" | sudo tee -a rootfs/etc/modules
	echo -e 'auto usb0\nallow-hotplug usb0\niface usb0 inet static\n  address 10.0.0.1\n  netmask 255.255.255.0\n  gateway 10.0.0.2'| sudo tee -a rootfs/etc/network/interfaces
	echo "usbarmory" | sudo tee rootfs/etc/hostname
	echo "usbarmory  ALL=(ALL) NOPASSWD: ALL" | sudo tee -a rootfs/etc/sudoers
	echo -e "127.0.1.1\tusbarmory" | sudo tee -a rootfs/etc/hosts
# the hash matches password 'usbarmory'
	sudo chroot rootfs /usr/sbin/useradd -s /bin/bash -p '$$6$$bE13Mtqs3F$$VvaDyPBE6o/Ey0sbyIh5/8tbxBuSiRlLr5rai5M7C70S22HDwBvtu2XOFsvmgRMu.tPdyY6ZcjRrbraF.dWL51' -m usbarmory
	sudo rm rootfs/etc/ssh/ssh_host_*
	sudo cp linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb rootfs/tmp/
	sudo chroot rootfs /usr/bin/dpkg -i /tmp/linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
	sudo cp linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb rootfs/tmp/
	sudo chroot rootfs /usr/bin/dpkg -i /tmp/linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
	sudo rm rootfs/tmp/linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
	sudo cp armoryctl_${ARMORYCTL_VER}_armhf.deb rootfs/tmp/
	sudo chroot rootfs /usr/bin/dpkg -i /tmp/armoryctl_${ARMORYCTL_VER}_armhf.deb
	sudo rm rootfs/tmp/armoryctl_${ARMORYCTL_VER}_armhf.deb
	sudo cp prebuilt/${LINUX_VER}/dcp_derive rootfs/usr/bin
	sudo chmod +x rootfs/usr/bin/dcp_derive
	echo "/dev/${ROOTFS_DEV} 0x100000 0x2000 0x2000" | sudo tee rootfs/etc/fw_env.config
	sudo chroot rootfs apt-get clean
	sudo chroot rootfs fake-hwclock
	sudo rm rootfs/usr/bin/qemu-arm-static
	sudo umount rootfs
	# clean-up luks
	@if test "${LUKS}" = "on"; then \
		cryptsetup luksClose /dev/mapper/${ROOTFS_MAPPER_NAME}; \
		sudo /usr/sbin/kpartx -d $(LOSETUP_DEV); \
		sudo /sbin/losetup -d $(LOSETUP_DEV); \
	fi

#### debian-xz ####

IMAGE_DEPS := check_params
ifeq ($(BOOTLOADER),armory-boot)
	ifeq ($(SIGNED), on)
		IMAGE_DEPS += armory-boot-signed.imx
	else
		IMAGE_DEPS += armory-boot.imx
	endif
endif
ifeq ($(BOOTLOADER),u-boot)
	IMAGE_DEPS += u-boot-${UBOOT_VER}/u-boot.bin
endif
usbarmory-${IMG_VERSION}.img.xz: usbarmory-${IMG_VERSION}.img $(IMAGE_DEPS)
	@if test "${BOOTLOADER}" = "armory-boot"; then \
		if test "${SIGNED}" = "on"; then \
			sudo dd if=armory-boot-master/armory-boot-signed.imx of=usbarmory-${IMG_VERSION}.img bs=512 seek=2 conv=fsync conv=notrunc; \
		else \
			sudo dd if=armory-boot-master/armory-boot.imx of=usbarmory-${IMG_VERSION}.img bs=512 seek=2 conv=fsync conv=notrunc; \
		fi \
	else \
		sudo dd if=u-boot-${UBOOT_VER}/u-boot-dtb.imx of=usbarmory-${IMG_VERSION}.img bs=512 seek=2 conv=fsync conv=notrunc; \
	fi
	xz -k usbarmory-${IMG_VERSION}.img

#### busybox ####
busybox-${BUSYBOX_VER}.tar.bz2:
	wget https://www.busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2 -O busybox-${BUSYBOX_VER}.tar.bz2
	wget https://www.busybox.net/downloads/busybox-${BUSYBOX_VER}.tar.bz2.sig -O busybox-${BUSYBOX_VER}.tar.bz2.sig

busybox-bin-${BUSYBOX_VER}: busybox-${BUSYBOX_VER}.tar.bz2
	gpg --verify busybox-${BUSYBOX_VER}.tar.bz2.sig
	tar xfm busybox-${BUSYBOX_VER}.tar.bz2
	cd busybox-${BUSYBOX_VER} && \
		make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig && \
		sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config && \
		make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- install

#### init script ####
init:
	@if test "${LUKS}" == "off"; then \
		cp init-no-luks init; \
	else \
		if test "${DCP_PASSWORD}" == ""; then \
			cp init-luks-unlock init; \
			sed -i "s/{LUKS_PASSWORD}/${LUKS_PASSWORD}/g" init; \
		else \
			if test "${DIVERSIFIER}" == ""; then \
				echo "Password diversifier is required when dcp is on"; \
				exit 1; \
			fi; \
			cp init-luks-dcp init; \
			sed -i "s/{DCP_PASSWORD}/${DCP_PASSWORD}/g" init; \
			sed -i "s/{DIVERSIFIER}/${DIVERSIFIER}/g" init; \
		fi; \
	fi
	@if test "${TEST_INIT}" == "on"; then \
		cp init-test init; \
	fi
	sed -i "s/{ROOTFS_DEV}/${ROOTFS_DEV}/g" init

#### initramfs ####
initramfs: busybox-bin-${BUSYBOX_VER} init
	mkdir -pv initramfs/{bin,dev,sbin,etc,run,boot,proc,sys/kernel/debug,usr/{bin,sbin},lib/modules,mnt/root,root}
	cp -av busybox-${BUSYBOX_VER}/_install/* initramfs
	cp init initramfs
	chmod +x initramfs/init
	mkdir -p initramfs/dev
	cp prebuilt/${LINUX_VER}/dcp_derive initramfs/usr/sbin
	cp prebuilt/${LINUX_VER}/armoryctl initramfs/usr/sbin
	chmod +x initramfs/usr/sbin/dcp_derive
	chmod +x initramfs/usr/sbin/armoryctl
	cp -av prebuilt/${LINUX_VER}/modules initramfs/lib
	mkdir -p initramfs/lib/modules/${LINUX_VER}-0
	@if test "${IMX}" = "imx6ulz"; then \
		cp prebuilt/${LINUX_VER}/mxs-dcp.ko initramfs/lib/modules/${LINUX_VER}-0/extra; \
	fi
	@if test "${IMX}" = "imx6ul"; then \
		cp prebuilt/${LINUX_VER}/caam_keyblob.ko initramfs/lib/modules/${LINUX_VER}-0/extra; \
	fi
	cd initramfs/dev && \
		mknod -m 622 console c 5 1 && \
		mknod -m 622 tty0 c 4 0
	cp -av prebuilt/${LINUX_VER}/cryptsetup/* initramfs
	echo "leds_gpio" | sudo tee -a initramfs/etc/modules
	echo "led_class" | sudo tee -a initramfs/etc/modules
	echo "mxs_dcp" | sudo tee -a initramfs/etc/modules
	echo "algif_rng" | sudo tee -a initramfs/etc/modules
	echo "algif_skcipher" | sudo tee -a initramfs/etc/modules
	echo "algif_hash" | sudo tee -a initramfs/etc/modules
	echo "af_alg" | sudo tee -a initramfs/etc/modules
	echo "dm_crypt" | sudo tee -a initramfs/etc/modules

#### linux ####

linux-${LINUX_VER}.tar.xz:
	wget https://www.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VER}.tar.xz -O linux-${LINUX_VER}.tar.xz
	wget https://www.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VER}.tar.sign -O linux-${LINUX_VER}.tar.sign

linux-${LINUX_VER}/arch/arm/boot/zImage: check_params initramfs linux-${LINUX_VER}.tar.xz
	@if [ ! -d "linux-${LINUX_VER}" ]; then \
		unxz --keep linux-${LINUX_VER}.tar.xz; \
		gpg --verify linux-${LINUX_VER}.tar.sign; \
		tar xfm linux-${LINUX_VER}.tar && cd linux-${LINUX_VER}; \
	fi
	wget ${USBARMORY_REPO}/software/kernel_conf/mark-two/usbarmory_linux-${LINUX_VER_MAJOR}.config -O linux-${LINUX_VER}/.config
	wget ${USBARMORY_REPO}/software/kernel_conf/mark-two/${IMX}-usbarmory.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dts
	sed -i 's/CONFIG_INITRAMFS_SOURCE=""/CONFIG_INITRAMFS_SOURCE="\/opt\/armory\/initramfs"/g' linux-${LINUX_VER}/.config
	cd linux-${LINUX_VER} && \
		KBUILD_BUILD_USER=${KBUILD_BUILD_USER} \
		KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} \
		LOCALVERSION=${LOCALVERSION} \
		ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
		make -j${JOBS} zImage modules ${IMX}-usbarmory.dtb

#### mxc-scc2 ####

mxc-scc2-master.zip:
	wget ${MXC_SCC2_REPO}/archive/master.zip -O mxc-scc2-master.zip

mxc-scc2-master: mxc-scc2-master.zip
	unzip -o mxc-scc2-master.zip

mxc-scc2-master/mxc-scc2.ko: mxc-scc2-master linux-${LINUX_VER}/arch/arm/boot/zImage
	cd mxc-scc2-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all

#### mxs-dcp ####

mxs-dcp-master.zip:
	wget ${MXS_DCP_REPO}/archive/master.zip -O mxs-dcp-master.zip

mxs-dcp-master: mxs-dcp-master.zip
	unzip -o mxs-dcp-master.zip

mxs-dcp-master/mxs-dcp.ko: mxs-dcp-master linux-${LINUX_VER}/arch/arm/boot/zImage
	cd mxs-dcp-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all

#### caam-keyblob ####

caam-keyblob-master.zip:
	wget ${CAAM_KEYBLOB_REPO}/archive/master.zip -O caam-keyblob-master.zip

caam-keyblob-master: caam-keyblob-master.zip
	unzip -o caam-keyblob-master.zip

caam-keyblob-master/caam-keyblob.ko: caam-keyblob-master linux-${LINUX_VER}/arch/arm/boot/zImage
	cd caam-keyblob-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all

#### linux-image-deb ####

KERNEL_DEPS := check_params
KERNEL_DEPS += linux-${LINUX_VER}/arch/arm/boot/zImage
KERNEL_DEPS += mxs-dcp caam-keyblob
linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb: $(KERNEL_DEPS)
	mkdir -p linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/{DEBIAN,boot,lib/modules}
	cat control_template_linux | \
		sed -e 's/XXXX/${LINUX_VER_MAJOR}/'          | \
		sed -e 's/YYYY/${LINUX_VER}${LOCALVERSION}/' | \
		sed -e 's/USB armory/USB armory mark-two/' \
		> linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control
	sed -i -e 's/${LINUX_VER_MAJOR}-usbarmory/${LINUX_VER_MAJOR}-usbarmory-mark-two/' linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control
	cd linux-${LINUX_VER} && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm modules_install
	@if test "${IMX}" = "imx6ulz"; then \
		cd mxs-dcp-master && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm KERNEL_SRC=../linux-${LINUX_VER} modules_install; \
	fi
	@if test "${IMX}" = "imx6ul"; then \
		cd caam-keyblob-master && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm KERNEL_SRC=../linux-${LINUX_VER} modules_install; \
	fi
	rm linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/lib/modules/${LINUX_VER}${LOCALVERSION}/{build,source}
	chmod 755 linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN
	fakeroot dpkg-deb -b linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb

#### linux-headers-deb ####

HEADER_DEPS := check_params
HEADER_DEPS += linux-${LINUX_VER}/arch/arm/boot/zImage
linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb: $(HEADER_DEPS)
	mkdir -p linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/{DEBIAN,boot,lib/modules/${LINUX_VER}${LOCALVERSION}/build}
	cd linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/lib/modules/${LINUX_VER}${LOCALVERSION} ; ln -sf build source
	cat control_template_linux-headers | \
		sed -e 's/XXXX/${LINUX_VER_MAJOR}/'          | \
		sed -e 's/YYYY/${LINUX_VER}${LOCALVERSION}/' | \
		sed -e 's/ZZZZ/linux-image-${LINUX_VER_MAJOR}-usbarmory (=${LINUX_VER}${LOCALVERSION})/' | \
		sed -e 's/USB armory/USB armory mark-two/' \
		> linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control
	sed -i -e 's/${LINUX_VER_MAJOR}-usbarmory/${LINUX_VER_MAJOR}-usbarmory-mark-two/' linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control
	cd linux-${LINUX_VER} && make INSTALL_HDR_PATH=../linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/lib/modules/${LINUX_VER}${LOCALVERSION}/build ARCH=arm headers_install
	chmod 755 linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN
	fakeroot dpkg-deb -b linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb

#### armoryctl ####

armoryctl-${ARMORYCTL_VER}.zip:
	wget ${ARMORYCTL_REPO}/archive/v${ARMORYCTL_VER}.zip -O armoryctl-v${ARMORYCTL_VER}.zip

armoryctl-${ARMORYCTL_VER}: armoryctl-${ARMORYCTL_VER}.zip
	unzip -o armoryctl-v${ARMORYCTL_VER}.zip

armoryctl-${ARMORYCTL_VER}/armoryctl: armoryctl-${ARMORYCTL_VER}
	cd armoryctl-${ARMORYCTL_VER} && GOPATH=/tmp/go GOARCH=arm make

#### armoryctl-deb ####

armoryctl_${ARMORYCTL_VER}_armhf.deb: armoryctl-${ARMORYCTL_VER}/armoryctl
	mkdir -p armoryctl_${ARMORYCTL_VER}_armhf/{DEBIAN,sbin}
	cat control_template_armoryctl | \
		sed -e 's/YYYY/${ARMORYCTL_VER}/' \
		> armoryctl_${ARMORYCTL_VER}_armhf/DEBIAN/control
	cp -r armoryctl-${ARMORYCTL_VER}/armoryctl armoryctl_${ARMORYCTL_VER}_armhf/sbin
	chmod 755 armoryctl_${ARMORYCTL_VER}_armhf/DEBIAN
	fakeroot dpkg-deb -b armoryctl_${ARMORYCTL_VER}_armhf armoryctl_${ARMORYCTL_VER}_armhf.deb

#### targets ####

.PHONY: u-boot debian debian-xz linux linux-image-deb linux-headers-deb
.PHONY: mxs-dcp mxc-scc2 caam-keyblob armoryctl armoryctl-deb busybox
.PHONY: boot.img

u-boot: u-boot-${UBOOT_VER}/u-boot.bin
debian: usbarmory-${IMG_VERSION}.img
debian-xz: usbarmory-${IMG_VERSION}.img.xz
boot.img: usbarmory-boot-${IMG_VERSION}.img
linux: linux-${LINUX_VER}/arch/arm/boot/zImage
linux-image-deb: linux-image-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
linux-headers-deb: linux-headers-${LINUX_VER_MAJOR}-usbarmory-${LINUX_VER}${LOCALVERSION}_armhf.deb
mxs-dcp: mxs-dcp-master/mxs-dcp.ko
busybox: busybox-bin-${BUSYBOX_VER}
mxc-scc2: mxc-scc2-master/mxc-scc2.ko
caam-keyblob: caam-keyblob-master/caam-keyblob.ko
armoryctl: armoryctl-${ARMORYCTL_VER}/armoryctl
armoryctl-deb: armoryctl_${ARMORYCTL_VER}_armhf.deb
armory-boot: armory-boot.imx
armory-boot-signed: armory-boot-signed.imx

release: check_params usbarmory-${IMG_VERSION}.img.xz
	sha256sum usbarmory-${IMG_VERSION}.img.xz > usbarmory-${IMG_VERSION}.img.xz.sha256
	@if test "${LUKS}" = "on"; then \
		echo -e "The LUKS password is: ${LUKS_PASSWORD}"; \
	fi

clean:
	-rm -fr armoryctl* linux-* linux-image-* linux-headers-* u-boot-* busybox-* initramfs cryptsetup
	-rm -fr mxc-scc2-master* mxs-dcp-master* caam-keyblob-master* armory-boot-master*
	-rm -f usbarmory-*
	-rm -f init
	-sudo umount -f rootfs
	-sudo umount -f bootfs
	-rmdir bootfs
	-rmdir rootfs
