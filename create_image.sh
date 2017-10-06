#!/bin/bash -e

OUTFILE="$1"
if [ ! "$OUTFILE" ]; then
    echo "Syntax: $0 <output file>" >&2
    exit 1
fi
if [ -e "$OUTFILE" ]; then
    echo "$OUTFILE already exists, please remove it if you want to overwrite it"
    exit 1
fi

# Check for dependencies
if [ ! "$CROSS_COMPILE_ARMV6" ]; then
    echo "Please define the CROSS_COMPILE_ARMV6 variable" >&2
    exit 1
fi
if [ ! "$CROSS_COMPILE_ARMV7" ]; then
    echo "Please define the CROSS_COMPILE_ARMV7 variable" >&2
    exit 1
fi
if [ ! "$CROSS_COMPILE_AARCH64" ]; then
    echo "Please define the CROSS_COMPILE_AARCH64 variable" >&2
    exit 1
fi
which ${CROSS_COMPILE_ARMV6}gcc >/dev/null || exit 1
which ${CROSS_COMPILE_ARMV7}gcc >/dev/null || exit 1
which ${CROSS_COMPILE_AARCH64}gcc >/dev/null || exit 1
which make >/dev/null || exit 1
which git >/dev/null || exit 1
which fallocate >/dev/null || exit 1
which mkfs.vfat >/dev/null || exit 1
which fdisk >/dev/null || exit 1
which kpartx >/dev/null || exit 1
which dtc >/dev/null || exit 1
which lscpu >/dev/null || exit 1
which mkimage >/dev/null || exit 1

NR_CPUS=$(lscpu -p | grep -v '#' | wc -l)

# Download firmware if not already available
if [ ! -d firmware ]; then
    git clone --depth 1 -b stable https://github.com/raspberrypi/firmware.git
fi

# Download u-boot if not already available
if [ ! -d u-boot ]; then
    git clone --depth 1 -b rpi-stable https://github.com/agraf/u-boot.git
fi

# Download u-boot if not already available
if [ ! -d grub ]; then
    # XXX bump to newer versions automatically
    git clone --depth 1 -b grub-2.02-rc2 git://git.savannah.gnu.org/grub.git
    (
        cd grub
        ./autogen.sh

        # Patch DNS to IPv4 only - IPv6 kept failing for me
        sed -i s/DNS_OPTION_PREFER_IPV4/DNS_OPTION_IPV4/ grub-core/net/bootp.c
    )
fi

function build_arch()
{
    TARGET_ARCH="$1"

    case "$TARGET_ARCH" in
    armv6)
        UBOOT_CONFIG=rpi_defconfig
        UBOOT_KERNEL=kernel.img
        export CROSS_COMPILE="$CROSS_COMPILE_ARMV6"
	GRUB_TARGET=arm
	GRUB_TYPE=arm-efi
        # Use armv5 target for now as gcc7 compiles wrong code with march=armv6:
        #   https://gcc.gnu.org/bugzilla/show_bug.cgi?id=82445
	GRUB_GCC="${CROSS_COMPILE}gcc -march=armv5 -marm"
        ;;
    armv7)
        UBOOT_CONFIG=rpi_2_defconfig
        UBOOT_KERNEL=kernel7.img
        export CROSS_COMPILE="$CROSS_COMPILE_ARMV7"
	GRUB_TARGET=arm
	GRUB_TYPE=arm-efi
	GRUB_GCC="${CROSS_COMPILE}gcc"
        ;;
    aarch64)
        UBOOT_CONFIG=rpi_3_defconfig
        UBOOT_KERNEL=kernel8.img
        export CROSS_COMPILE="$CROSS_COMPILE_AARCH64"
	GRUB_TARGET=aarch64
	GRUB_TYPE=arm64-efi
	GRUB_GCC="${CROSS_COMPILE}gcc"
        ;;
    esac

    # Build Das U-Boot
    (
        cd u-boot
        make $UBOOT_CONFIG
        make -j${NR_CPUS}
        mv u-boot.bin $UBOOT_KERNEL
        make clean
    )

    # Build grub
    (
        cd grub
        BUILDDIR="build-$TARGET_ARCH"
        rm -rf "$BUILDDIR"
        mkdir -p "$BUILDDIR"
        cd "$BUILDDIR"
        ../configure --disable-werror					\
		     TARGET_CC="$GRUB_GCC"				\
		     TARGET_OBJCOPY=${CROSS_COMPILE}objcopy		\
		     TARGET_STRIP=${CROSS_COMPILE}strip			\
		     TARGET_NM=${CROSS_COMPILE}nm			\
		     TARGET_RANLIB=${CROSS_COMPILE}ranlib		\
		     --prefix=$(pwd)					\
		     --target="$GRUB_TARGET" --with-platform=efi
        make -j${NR_CPUS}
        make install
        ( cd ../../; tar c grub.cfg ) > grub.memdisk
        ./bin/grub-mkimage -m grub.memdisk -C xz -O $GRUB_TYPE -o grub.efi -p "(memdisk)/" $(find lib* -name '*.mod' | cut -d '/' -f 4 | cut -d . -f 1)
    )
}

for i in armv6 armv7 aarch64; do
    build_arch "$i"
done

# Create a 20MB image with 1 active FAT32 partition
fallocate -l $(( 20 * 1024 * 1024 )) "$OUTFILE"
cat > fdisk.cmd <<-EOF
	o
	n
	p
	1
	
	
	t
	c
	a
	w
EOF
fdisk -t dos "$OUTFILE" < fdisk.cmd
rm -f fdisk.cmd

FATPART=$(kpartx -sav "$OUTFILE" 2>/dev/null | cut -d ' ' -f 3)
mkfs.vfat "/dev/mapper/${FATPART}"
mkdir -p mnt
mount "/dev/mapper/${FATPART}" mnt

# Copy all files to the FAT partition
cp firmware/boot/{start,fixup,boot,LIC,COP}* mnt/
cp u-boot/kernel*img mnt/
mkdir -p mnt/efi/boot
cp grub/build-armv6/grub.efi mnt/grub_armv6.efi
cp grub/build-aarch64/grub.efi mnt/grub_aarch64.efi
cp grub.cfg mnt/
cp config.txt mnt/
mkimage -C none -A arm -T script -d boot.script mnt/boot.scr

# Clean up
umount mnt
dmsetup remove "${FATPART}"
losetup -d /dev/$(echo "$FATPART" | cut -d p -f -2)

echo
echo "Image created successfully"
