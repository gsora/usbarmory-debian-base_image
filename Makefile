SHELL = /bin/bash
JOBS=16
BASE_DIR=${shell pwd}
CROSS_COMPILE=arm-linux-gnueabihf-

LINUX_VER=5.4.38
LINUX_VER_MAJOR=${shell echo ${LINUX_VER} | cut -d '.' -f1,2}
KBUILD_BUILD_USER=usbarmory
KBUILD_BUILD_HOST=f-secure-foundry
LOCALVERSION=-0
UBOOT_VER=2019.07
ARMORYCTL_VER=1.0
APT_GPG_KEY=CEADE0CF01939B21

USBARMORY_REPO=https://raw.githubusercontent.com/f-secure-foundry/usbarmory/master
ARMORYCTL_REPO=https://github.com/f-secure-foundry/armoryctl
MXC_SCC2_REPO=https://github.com/f-secure-foundry/mxc-scc2
MXS_DCP_REPO=https://github.com/f-secure-foundry/mxs-dcp
CAAM_KEYBLOB_REPO=https://github.com/f-secure-foundry/caam-keyblob
IMG_VERSION=${V}-debian_buster-base_image-$(shell /bin/date -u "+%Y%m%d")
LOSETUP_DEV=$(shell /sbin/losetup -f)

OPTEE_OS_REPO=https://github.com/OP-TEE/optee_os
OPTEE_CLIENT_REPO=https://github.com/OP-TEE/optee_client
OPTEE_TEST_REPO=https://github.com/OP-TEE/optee_test

OPTEE_OS_COMMIT=7fdadfdb9678d1217c6c161116dec8342642fb0b
UTEE_NS_LOAD_ADDR=0x80800000
UTEE_DT_ADDR=0x82000000
UTEE_UART_ADDR=0x021E8000
OPTEE_OS_LOAD_ADDR=0x9DFFFFE4
OPTEE_OS_ENTRY_POINT=0x9E000000

OPTEE_CLIENT_COMMIT=e9e55969d76ddefcb5b398e592353e5c7f5df198

OPTEE_TEST_COMMIT=f461e1d47fcc82eaa67508a3d796c11b7d26656e

.DEFAULT_GOAL := all

V ?= mark-two
BOOT ?= uSD

check_version:
	@if test "${V}" = "mark-one"; then \
		if test "${BOOT}" != "uSD"; then \
			echo "invalid target, mark-one BOOT options are: uSD"; \
			exit 1; \
		elif test "${IMX}" != "imx53"; then \
			echo "invalid target, mark-one IMX options are: imx53"; \
			exit 1; \
		fi \
	elif test "${V}" = "mark-two"; then \
		if test "${BOOT}" != "uSD" && test "${BOOT}" != eMMC; then \
			echo "invalid target, mark-two BOOT options are: uSD, eMMC"; \
			exit 1; \
		elif test "${IMX}" != "imx6ul" && test "${IMX}" != "imx6ulz"; then \
			echo "invalid target, mark-two IMX options are: imx6ul, imx6ulz"; \
			exit 1; \
		fi \
	else \
		echo "invalid target - V options are: mark-one, mark-two"; \
		exit 1; \
	fi
	@echo "target: USB armory V=${V} IMX=${IMX} BOOT=${BOOT}"

usbarmory-${IMG_VERSION}.raw:
	truncate -s 3500MiB usbarmory-${IMG_VERSION}.raw
	sudo /sbin/parted usbarmory-${IMG_VERSION}.raw --script mklabel msdos
	sudo /sbin/parted usbarmory-${IMG_VERSION}.raw --script mkpart primary ext4 5M 100%

debian: check_version usbarmory-${IMG_VERSION}.raw
	sudo /sbin/losetup $(LOSETUP_DEV) usbarmory-${IMG_VERSION}.raw -o 5242880 --sizelimit 3500MiB
	sudo /sbin/mkfs.ext4 -F $(LOSETUP_DEV)
	sudo /sbin/losetup -d $(LOSETUP_DEV)
	mkdir -p rootfs
	sudo mount -o loop,offset=5242880 -t ext4 usbarmory-${IMG_VERSION}.raw rootfs/
	sudo update-binfmts --enable qemu-arm
	sudo qemu-debootstrap \
		--include=ssh,sudo,ntpdate,fake-hwclock,openssl,vim,nano,cryptsetup,lvm2,locales,less,cpufrequtils,isc-dhcp-server,haveged,rng-tools,whois,iw,wpasupplicant,dbus,apt-transport-https,dirmngr,ca-certificates,u-boot-tools,mmc-utils,gnupg \
		--arch=armhf buster rootfs http://ftp.debian.org/debian/
	sudo install -m 755 -o root -g root conf/rc.local rootfs/etc/rc.local
	sudo install -m 644 -o root -g root conf/sources.list rootfs/etc/apt/sources.list
	sudo install -m 644 -o root -g root conf/dhcpd.conf rootfs/etc/dhcp/dhcpd.conf
	sudo install -m 644 -o root -g root conf/usbarmory.conf rootfs/etc/modprobe.d/usbarmory.conf
	sudo sed -i -e 's/INTERFACESv4=""/INTERFACESv4="usb0"/' rootfs/etc/default/isc-dhcp-server
	echo "tmpfs /tmp tmpfs defaults 0 0" | sudo tee rootfs/etc/fstab
	echo -e "\nUseDNS no" | sudo tee -a rootfs/etc/ssh/sshd_config
	echo "nameserver 8.8.8.8" | sudo tee rootfs/etc/resolv.conf
	sudo chroot rootfs systemctl mask getty-static.service
	sudo chroot rootfs systemctl mask display-manager.service
	sudo chroot rootfs systemctl mask hwclock-save.service
	@if test "${V}" = "mark-one"; then \
		sudo chroot rootfs systemctl mask rng-tools.service; \
	fi
	@if test "${V}" = "mark-two"; then \
		sudo install -m 644 -o root -g root conf/tee-supplicant.service rootfs/etc/systemd/system/tee-supplicant.service; \
		sudo chroot rootfs systemctl mask haveged.service; \
		sudo chroot rootfs systemctl daemon-reload; \
		sudo chroot rootfs systemctl enable tee-supplicant.service; \
	fi
	sudo wget https://keys.inversepath.com/gpg-andrej.asc -O rootfs/tmp/gpg-andrej.asc
	sudo wget https://keys.inversepath.com/gpg-andrea.asc -O rootfs/tmp/gpg-andrea.asc
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
	sudo cp linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf.deb rootfs/tmp/
	sudo chroot rootfs /usr/bin/dpkg -i /tmp/linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf.deb
	sudo rm rootfs/tmp/linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf.deb
	@if test "${V}" = "mark-two"; then \
		set +x ;\
		sudo cp armoryctl_${ARMORYCTL_VER}_armhf.deb rootfs/tmp/; \
		sudo chroot rootfs /usr/bin/dpkg -i /tmp/armoryctl_${ARMORYCTL_VER}_armhf.deb; \
		sudo rm rootfs/tmp/armoryctl_${ARMORYCTL_VER}_armhf.deb; \
		sudo cp optee_${OPTEE_OS_COMMIT}_armhf.deb rootfs/tmp/; \
		sudo chroot rootfs /usr/bin/dpkg -i /tmp/optee_${OPTEE_OS_COMMIT}_armhf.deb; \
		sudo cp optee-test_${OPTEE_TEST_COMMIT}_armhf.deb rootfs/tmp/; \
		sudo chroot rootfs /usr/bin/dpkg -i /tmp/optee-test_${OPTEE_TEST_COMMIT}_armhf.deb; \
		sudo cp tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf.deb rootfs/tmp/; \
		sudo chroot rootfs /usr/bin/dpkg -i /tmp/tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf.deb; \
		sudo rm rootfs/tmp/tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf.deb; \
		sudo rm rootfs/tmp/optee-test_${OPTEE_TEST_COMMIT}_armhf.deb; \
		sudo rm rootfs/tmp/optee_${OPTEE_OS_COMMIT}_armhf.deb; \
		if test "${BOOT}" = "uSD"; then \
			echo "/dev/mmcblk0 0x100000 0x2000 0x2000" | sudo tee rootfs/etc/fw_env.config; \
		else \
			echo "/dev/mmcblk1 0x100000 0x2000 0x2000" | sudo tee rootfs/etc/fw_env.config; \
		fi \
	fi
	sudo chroot rootfs apt-get clean
	sudo chroot rootfs fake-hwclock
	sudo rm rootfs/usr/bin/qemu-arm-static
	sudo umount rootfs

linux-${LINUX_VER}.tar.xz:
	wget https://www.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VER}.tar.xz -O linux-${LINUX_VER}.tar.xz
	wget https://www.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VER}.tar.sign -O linux-${LINUX_VER}.tar.sign

u-boot-${UBOOT_VER}.tar.bz2:
	wget ftp://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VER}.tar.bz2 -O u-boot-${UBOOT_VER}.tar.bz2
	wget ftp://ftp.denx.de/pub/u-boot/u-boot-${UBOOT_VER}.tar.bz2.sig -O u-boot-${UBOOT_VER}.tar.bz2.sig

linux-${LINUX_VER}/arch/arm/boot/zImage: check_version linux-${LINUX_VER}.tar.xz
	@if [ ! -d "linux-${LINUX_VER}" ]; then \
		unxz --keep linux-${LINUX_VER}.tar.xz; \
		gpg --verify linux-${LINUX_VER}.tar.sign; \
		tar xf linux-${LINUX_VER}.tar && cd linux-${LINUX_VER}; \
	fi
	wget ${USBARMORY_REPO}/software/kernel_conf/${V}/usbarmory_linux-${LINUX_VER_MAJOR}.config -O linux-${LINUX_VER}/.config
	if test "${V}" = "mark-two"; then \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dts; \
		pushd linux-${LINUX_VER}; \
		patch -p0 < ../patches/linux-5.4-optee-armory-mk2.patch; \
		popd; \
	fi
	cd linux-${LINUX_VER} && \
		KBUILD_BUILD_USER=${KBUILD_BUILD_USER} \
		KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} \
		LOCALVERSION=${LOCALVERSION} \
		ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} \
		make -j${JOBS} zImage modules ${IMX}-usbarmory.dtb

u-boot-${UBOOT_VER}/u-boot.bin: check_version u-boot-${UBOOT_VER}.tar.bz2
	#gpg --verify u-boot-${UBOOT_VER}.tar.bz2.sig
	tar xf u-boot-${UBOOT_VER}.tar.bz2
	cd u-boot-${UBOOT_VER} && make distclean
	@if test "${V}" = "mark-one"; then \
		cd u-boot-${UBOOT_VER} && make usbarmory_config; \
	elif test "${V}" = "mark-two"; then \
		cd u-boot-${UBOOT_VER} && \
		wget ${USBARMORY_REPO}/software/u-boot/0001-ARM-mx6-add-support-for-USB-armory-Mk-II-board.patch && \
		wget ${USBARMORY_REPO}/software/u-boot/0001-Drop-linker-generated-array-creation-when-CONFIG_CMD.patch && \
		patch -p1 < 0001-ARM-mx6-add-support-for-USB-armory-Mk-II-board.patch && \
		patch -p1 < 0001-Drop-linker-generated-array-creation-when-CONFIG_CMD.patch && \
		patch -p0 < ../patches/boot-utee-usbarmory-mk2.patch; \
		make usbarmory-mark-two_defconfig; \
		sed -i -e 's/# CONFIG_IMAGE_FORMAT_LEGACY is not set/CONFIG_IMAGE_FORMAT_LEGACY=y/' .config;\
		if test "${BOOT}" = "eMMC"; then \
			sed -i -e 's/CONFIG_SYS_BOOT_DEV_MICROSD=y/# CONFIG_SYS_BOOT_DEV_MICROSD is not set/' .config; \
			sed -i -e 's/# CONFIG_SYS_BOOT_DEV_EMMC is not set/CONFIG_SYS_BOOT_DEV_EMMC=y/' .config; \
		fi \
	fi
	cd u-boot-${UBOOT_VER} && CROSS_COMPILE=${CROSS_COMPILE} ARCH=arm make -j${JOBS}

mxc-scc2-master.zip: check_version
	@if test "${IMX}" = "imx53"; then \
		wget ${MXC_SCC2_REPO}/archive/master.zip -O mxc-scc2-master.zip && \
		unzip -o mxc-scc2-master; \
	fi

mxs-dcp-master.zip: check_version
	@if test "${IMX}" = "imx6ulz"; then \
		wget ${MXS_DCP_REPO}/archive/master.zip -O mxs-dcp-master.zip && \
		unzip -o mxs-dcp-master; \
	fi

caam-keyblob-master.zip: check_version
	@if test "${IMX}" = "imx6ul"; then \
		wget ${CAAM_KEYBLOB_REPO}/archive/master.zip -O caam-keyblob-master.zip && \
		unzip -o caam-keyblob-master; \
	fi

armoryctl-${ARMORYCTL_VER}.zip: check_version
	@if test "${V}" = "mark-two"; then \
		wget ${ARMORYCTL_REPO}/archive/v${ARMORYCTL_VER}.zip -O armoryctl-v${ARMORYCTL_VER}.zip && \
		unzip -o armoryctl-v${ARMORYCTL_VER}.zip; \
	fi

linux: linux-${LINUX_VER}/arch/arm/boot/zImage

mxc-scc2: mxc-scc2-master.zip linux
	@if test "${IMX}" = "imx53"; then \
		cd mxc-scc2-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all; \
	fi

mxs-dcp: mxs-dcp-master.zip linux
	@if test "${IMX}" = "imx6ulz"; then \
		cd mxs-dcp-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all; \
	fi

caam-keyblob: caam-keyblob-master.zip linux
	@if test "${IMX}" = "imx6ul"; then \
		cd caam-keyblob-master && make KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} KERNEL_SRC=../linux-${LINUX_VER} -j${JOBS} all; \
	fi

armoryctl: armoryctl-${ARMORYCTL_VER}.zip
	@if test "${V}" = "mark-two"; then \
		cd armoryctl-${ARMORYCTL_VER} && GOPATH=/tmp/go GOARCH=arm make; \
	fi

extra-dtb: check_version linux
	@if test "${V}" = "mark-one"; then \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/usbarmory_linux-${LINUX_VER_MAJOR}.config -O linux-${LINUX_VER}/.config; \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory-host.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-host.dts; \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory-gpio.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-gpio.dts; \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory-spi.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-spi.dts; \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory-i2c.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-i2c.dts; \
		wget ${USBARMORY_REPO}/software/kernel_conf/${V}/${IMX}-usbarmory-scc2.dts -O linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-scc2.dts; \
		cd linux-${LINUX_VER} && KBUILD_BUILD_USER=${KBUILD_BUILD_USER} KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST} LOCALVERSION=${LOCALVERSION} ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} make -j${JOBS} ${IMX}-usbarmory-host.dtb ${IMX}-usbarmory-gpio.dtb ${IMX}-usbarmory-spi.dtb ${IMX}-usbarmory-i2c.dtb ${IMX}-usbarmory-scc2.dtb; \
	fi

linux-deb: check_version linux extra-dtb mxc-scc2 mxs-dcp caam-keyblob
	mkdir -p linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/{DEBIAN,boot,lib/modules}
	cat control_template_linux | \
		sed -e 's/XXXX/${LINUX_VER_MAJOR}/'          | \
		sed -e 's/YYYY/${LINUX_VER}${LOCALVERSION}/' | \
		sed -e 's/USB armory/USB armory ${V}/' \
		> linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control
	@if test "${V}" = "mark-two"; then \
		sed -i -e 's/${LINUX_VER_MAJOR}-usbarmory/${LINUX_VER_MAJOR}-usbarmory-mark-two/' \
		linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN/control; \
	fi
	cp -r linux-${LINUX_VER}/arch/arm/boot/zImage linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/zImage-${LINUX_VER}${LOCALVERSION}-usbarmory
	cp -r linux-${LINUX_VER}/.config linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/config-${LINUX_VER}${LOCALVERSION}-usbarmory
	cp -r linux-${LINUX_VER}/System.map linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/System.map-${LINUX_VER}${LOCALVERSION}-usbarmory
	cd linux-${LINUX_VER} && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm modules_install
	cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb
	@if test "${IMX}" = "imx53"; then \
		cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-host.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-host-${LINUX_VER}${LOCALVERSION}.dtb; \
		cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-spi.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-spi-${LINUX_VER}${LOCALVERSION}.dtb; \
		cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-gpio.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-gpio-${LINUX_VER}${LOCALVERSION}.dtb; \
		cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-i2c.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-i2c-${LINUX_VER}${LOCALVERSION}.dtb; \
		cp -r linux-${LINUX_VER}/arch/arm/boot/dts/${IMX}-usbarmory-scc2.dtb linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot/${IMX}-usbarmory-scc2-${LINUX_VER}${LOCALVERSION}.dtb; \
		cd mxc-scc2-master && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm KERNEL_SRC=../linux-${LINUX_VER} modules_install; \
	fi
	@if test "${IMX}" = "imx6ulz"; then \
		cd mxs-dcp-master && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm KERNEL_SRC=../linux-${LINUX_VER} modules_install; \
	fi
	@if test "${IMX}" = "imx6ul"; then \
		cd caam-keyblob-master && make INSTALL_MOD_PATH=../linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf ARCH=arm KERNEL_SRC=../linux-${LINUX_VER} modules_install; \
	fi
	cd linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot ; ln -sf zImage-${LINUX_VER}${LOCALVERSION}-usbarmory zImage
	cd linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot ; ln -sf ${IMX}-usbarmory-default-${LINUX_VER}${LOCALVERSION}.dtb ${IMX}-usbarmory.dtb
	cd linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/boot ; ln -sf ${IMX}-usbarmory.dtb imx6ull-usbarmory.dtb
	rm linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/lib/modules/${LINUX_VER}${LOCALVERSION}/{build,source}
	chmod 755 linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf/DEBIAN
	fakeroot dpkg-deb -b linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf.deb

armoryctl-deb: check_version armoryctl
	mkdir -p armoryctl_${ARMORYCTL_VER}_armhf/{DEBIAN,sbin}
	cat control_template_armoryctl | \
		sed -e 's/YYYY/${ARMORYCTL_VER}/' \
		> armoryctl_${ARMORYCTL_VER}_armhf/DEBIAN/control
	cp -r armoryctl-${ARMORYCTL_VER}/armoryctl armoryctl_${ARMORYCTL_VER}_armhf/sbin
	chmod 755 armoryctl_${ARMORYCTL_VER}_armhf/DEBIAN
	fakeroot dpkg-deb -b armoryctl_${ARMORYCTL_VER}_armhf armoryctl_${ARMORYCTL_VER}_armhf.deb

u-boot: u-boot-${UBOOT_VER}/u-boot.bin

finalize: usbarmory-${IMG_VERSION}.raw u-boot-${UBOOT_VER}/u-boot.bin
	@if test "${V}" = "mark-one"; then \
		sudo dd if=u-boot-${UBOOT_VER}/u-boot.imx of=usbarmory-${IMG_VERSION}.raw bs=512 seek=2 conv=fsync conv=notrunc; \
	elif test "${V}" = "mark-two"; then \
		sudo dd if=u-boot-${UBOOT_VER}/u-boot-dtb.imx of=usbarmory-${IMG_VERSION}.raw bs=512 seek=2 conv=fsync conv=notrunc; \
	fi

compress:
	xz -k usbarmory-${IMG_VERSION}.raw
	zip -j usbarmory-${IMG_VERSION}.raw.zip usbarmory-${IMG_VERSION}.raw

uTee.optee: u-boot
	git clone ${OPTEE_OS_REPO}; \
	cd optee_os; \
	git checkout ${OPTEE_OS_COMMIT}; \
	make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} PLATFORM=imx-mx6ulzevk ARCH=arm CFG_PAGEABLE_ADDR=0 CFG_NS_ENTRY_ADDR=${UTEE_NS_LOAD_ADDR} CFG_DT_ADDR=${UTEE_DT_ADDR} CFG_DT=y DEBUG=y CFG_TEE_CORE_LOG_LEVEL=4 CFG_TZC380=y CFG_UART_BASE=${UTEE_UART_ADDR} -j${JOBS}; \
	cd ..; \
	u-boot-${UBOOT_VER}/tools/mkimage -A arm -T kernel -O linux -C none -a ${OPTEE_OS_LOAD_ADDR} -e ${OPTEE_OS_ENTRY_POINT} -d optee_os/out/arm-plat-imx/core/tee.bin uTee.optee
	mkdir -p optee_${OPTEE_OS_COMMIT}_armhf/{DEBIAN,boot}
	cat control_template_optee | \
		sed -e 's/YYYY/1.0-${OPTEE_OS_COMMIT}/' \
		> optee_${OPTEE_OS_COMMIT}_armhf/DEBIAN/control
	cp -r uTee.optee optee_${OPTEE_OS_COMMIT}_armhf/boot
	chmod 755 optee_${OPTEE_OS_COMMIT}_armhf/DEBIAN
	fakeroot dpkg-deb -b optee_${OPTEE_OS_COMMIT}_armhf optee_${OPTEE_OS_COMMIT}_armhf.deb

optee_client: uTee.optee
	git clone ${OPTEE_CLIENT_REPO}; \
	cd optee_client; \
	git checkout ${OPTEE_CLIENT_COMMIT}; \
	make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE}; \
	cd ..; \
	mkdir -p tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf/{DEBIAN,sbin,lib}
	cat control_template_tee-supplicant | \
		sed -e 's/YYYY/1.0-${OPTEE_CLIENT_COMMIT}/' \
		> tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf/DEBIAN/control
	cp -r optee_client/out/tee-supplicant/tee-supplicant tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf/sbin
	cp -r optee_client/out/libteec/libteec* tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf/lib
	chmod 755 tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf/DEBIAN
	fakeroot dpkg-deb -b tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf tee-supplicant_${OPTEE_CLIENT_COMMIT}_armhf.deb

optee_test: optee_client
	git clone ${OPTEE_TEST_REPO}; \
	cd optee_test; \
	git checkout ${OPTEE_TEST_COMMIT}; \
	make ARCH=arm CROSS_COMPILE=${CROSS_COMPILE} \
		TA_DEV_KIT_DIR=${BASE_DIR}/optee_os/out/arm-plat-imx/export-ta_arm32 \
		OPTEE_CLIENT_EXPORT=${BASE_DIR}/optee_client/out/export/usr; \
	cd ..; \
	mkdir -p optee-test_${OPTEE_TEST_COMMIT}_armhf/{DEBIAN,sbin,lib/optee_armtz}
	cat control_template_optee-test | \
		sed -e 's/YYYY/1.0-${OPTEE_TEST_COMMIT}/' \
		> optee-test_${OPTEE_TEST_COMMIT}_armhf/DEBIAN/control
	cp -r optee_test/out/ta/*/*.ta optee-test_${OPTEE_TEST_COMMIT}_armhf/lib/optee_armtz
	cp -r optee_test/out/xtest/xtest optee-test_${OPTEE_TEST_COMMIT}_armhf/sbin
	chmod 755 optee-test_${OPTEE_TEST_COMMIT}_armhf/DEBIAN
	fakeroot dpkg-deb -b optee-test_${OPTEE_TEST_COMMIT}_armhf optee-test_${OPTEE_TEST_COMMIT}_armhf.deb

optee: uTee.optee optee_client optee_test

ifeq ($(V),mark-two)
all: check_version armoryctl-deb linux-deb optee debian u-boot finalize
else
all: check_version linux-deb debian u-boot finalize
endif

clean: check_version
	-rm -fr linux-${LINUX_VER}*
	-rm -fr u-boot-${UBOOT_VER}*
	-rm -fr linux-image-${LINUX_VER_MAJOR}-usbarmory-${V}_${LINUX_VER}${LOCALVERSION}_armhf*
	-rm -fr armoryctl*
	-rm -fr optee*
	-rm -fr tee-supplicant*
	-rm -fr uTee.optee
	-rm -fr mxc-scc2-master* mxs-dcp-master* caam-keyblob-master*
	-rm -f usbarmory-${V}-debian_buster-base_image-*.raw
	-sudo umount -f rootfs
	-rmdir rootfs
