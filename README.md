# rpi-instsd
Raspberry Pi UEFI SD image creator

This is a simple script that assembles a raw image file you can use to
teach your Raspberry Pi normal booting of distributions. With this, you
can either directly install a distribution from the network or using
a USB stick.

## Build requirements

You need the following packages on your host:

* Cross compilers for ARM and AArch64
* xz development packages (zypper in xz-devel)
* dtc (zypper in dtc)
* kpartx (zypper in kpartx)

For most of them, the script will warn you if the prerequisite is not met.

## Building

This command will give you a working sd.raw image which can then be
dd'ed onto an SD card to boot from.

```
$ su -
# export CROSS_COMPILE_ARMV6=...
# export CROSS_COMPILE_ARMV7=...
# export CROSS_COMPILE_AARCH64=...
# ./create_image.sh sd.raw
```

## Boot Flow

### Graphical vs Text mode

By default U-Boot will display grub on the graphical output. If you
want to use the serial console instead, press "t" there. The console
will get switched over automatically to serial and Linux will output
itself to serial too then.

### Media Boot

By default U-Boot will try to boot using default mechanisms from
SD, USB and Network. If any of these devices (in that order) provide
a bootable script or UEFI removable media binary, it will boot it.

### Fallback installer

If local and network boot failed, the image will fall back to a small
built-in grub binary that can boot into distributions installers
directly using HTTP.

Currently this method is only implemented for openSUSE on AArch64.
