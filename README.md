# USB armory Debian base image

The Makefile in this repository is based on the [official usbarmory debian image repo](https://github.com/f-secure-foundry/usbarmory-debian-base_image)

## Differences
* Able to customize bootloader (u-boot, armory-boot)
* Build image to use for secure boot (only with armory-boot)
* Able to customize boot partition size
* Separate `/boot` partition to enable LUKS encrypted root
* Initramfs with modules to setup LUKS encrypted root
* Pre-encrypted image
* Targets for update kernel image
* Customizable init script
* Build signed image
* Dropped support for Mark I (I have no device to test on)

## Prebuilt Modules
We run into chicken and egg situation with embedded modules for initramfs, initramfs is packaged by kernel during build and kernel modules are only built after the kernel is built. So the prebuilt folder will include prebuilt kernel modules so they can be packaged inside the initramfs, if you are unsure about the ones I packaged, replace the modules with ones you built. Make sure all the symlink is working.

## Pre-requisites

A Debian 9 installation with the following packages:

```
bc binfmt-support bzip2 fakeroot gcc gcc-arm-linux-gnueabihf git gnupg make parted rsync qemu-user-static wget xz-utils zip debootstrap sudo dirmngr bison flex libssl-dev kmod
```

Import the Linux signing GPG key:
```
gpg --keyserver hkp://keys.gnupg.net --recv-keys 38DBBDC86092693E
```

Import the U-Boot signing GPG key:
```
gpg --keyserver hkp://keys.gnupg.net --recv-keys 147C39FF9634B72C
```

Import the Busybox signing GPG key:
```
gpg --keyserver hkp://ha.pool.sks-keyservers.net --recv-keys C9E9416F76E610DBD09D040F47B70C55ACC9965B
```

The `loop` Linux kernel module must be enabled/loaded, also mind that the
Makefile relies on the ability to execute privileged commands via `sudo`.

## Docker pre-requisites

When building the image under Docker the `--privileged` option is required to
give privileges for handling loop devices, example:

```
docker build --rm -t armory ./
docker run --rm -it --privileged -v $(pwd):/opt/armory --name armory armory
```

On Mac OS X the build needs to be done in a case-sensitive filesystem. Such
filesystem can be created with `Disk Utility` by selecting `File > New Image >
Blank Image`, choosing `Size: 5GB` and `Format: APFS (Case-sensitive)`. Double
click on the created dmg file to mount it.

## Building

Launch the following command to download and build the image:

```
# For the USB armory Mk II (external microSD)
make IMX=imx6ulz BOOT=uSD

# For the USB armory Mk II (internal eMMC)
make IMX=imx6ulz BOOT=eMMC
```

## Building with LUKS encrypted rootfs
Launch the following command to download and build the image:

```
# For the USB armory Mk II (external microSD)
make IMX=imx6ulz BOOT=uSD LUKS=on

# For the USB armory Mk II (internal eMMC)
make IMX=imx6ulz BOOT=eMMC LUKS=on
```

The makefile will generate an random password using `openssl` and print it in the console. Look for the following text:

```
Creating luks partition with password: 8bf047879bf32a47676958d1307510ff5ae7f651
```

Make sure to nuke this keyslot once image is provisioned on the device and a new password is installed.

### The following output files are produced:

```
usbarmory-mark-two-debian_buster-base_image-YYYYMMDD.img
```

## Auto-unlocking LUKS
There are existing solutions using the Dropbear SSH unlock for the LUKS partition. Having to not embed an key in the system is able to make the drive unrecoverable if lost. For my own use cases, I plan to have the drive auto unlocked but also make sure it will provide similar security.

### DCP-derive
The LUKS partition password will be embedded in the boot partition, in the zImage. But this key is not the LUKS partitions plaintext key, its encrypted using the device's DCP and the OTPMK. Even when attacker extracted the key from the zImage, they have no way to decrypt it off device since the OTPMK is embedded in the processor and can not be read.

### Secure boot
When the encrypted key cannot be read by the attacker off device, how do we prevent them from reading it on device. We can't, but we are able to leverage secure boot and make sure the bootloader loading the kernel also the kernel itself + initramfs is not tampered with. This is the main reason why I chose to embed the initramfs inside the zImage, so the bootloader can just verify the zImage.

In conclusion, this method will not prevent attacker to boot your device once they have it in their possession. You will be responsible to hardening the device once its booted, make sure your ports are protected, password is strong and never run untrusted services without confirmation.

## Installation

**WARNING**: the following operations will destroy any previous contents on the
external microSD or internal eMMC storage.

**IMPORTANT**: `/dev/sdX`, `/dev/diskN` must be replaced with your microSD or
eMMC device (not eventual partitions), ensure that you are specifying the
correct one. Errors in target specification will result in disk corruption.

Linux (verify target from terminal using `dmesg`):
```
sudo dd if=usbarmory-*-debian_buster-base_image-YYYYMMDD.img of=/dev/sdX bs=1M conv=fsync
```

Mac OS X (verify target from terminal with `diskutil list`):
```
sudo dd if=usbarmory-*-debian_buster-base_image-YYYYMMDD.img of=/dev/rdiskN bs=1m
```

On Windows, and other OSes, alternatively the [Etcher](https://etcher.io)
utility can be used.

### Accessing the USB armory Mk II internal eMMC as USB storage device

Set the USB armory Mk II to boot in Serial Boot Loader by setting the boot
switch towards the microSD slot, without a microSD card connected. Connect the
USB Type-C interface to the host and verify that your host kernel successfully
detects the board:

```
usb 1-1: new high-speed USB device number 8 using xhci_hcd
usb 1-1: New USB device found, idVendor=15a2, idProduct=0080, bcdDevice= 0.01
usb 1-1: New USB device strings: Mfr=1, Product=2, SerialNumber=0
usb 1-1: Product: SE Blank 6ULL
usb 1-1: Manufacturer: Freescale SemiConductor Inc 
hid-generic 0003:15A2:0080.0003: hiddev96,hidraw1: USB HID v1.10 Device [Freescale SemiConductor Inc  SE Blank 6ULL] on usb-0000:00:14.0-1/input0
```

Load the [armory-ums](https://github.com/f-secure-foundry/armory-ums/releases)
firmware using the [armory-boot-usb](https://github.com/f-secure-foundry/armory-boot/tree/master/cmd/armory-boot-usb) utility:

```
sudo armory-boot-usb -i armory-ums.imx
```

Once loaded, the host kernel should detect a USB storage device, corresponding
to the internal eMMC.

## Connecting

After being booted, the image uses Ethernet over USB emulation (CDC Ethernet)
to communicate with the host, with assigned IP address 10.0.0.1 (using 10.0.0.2
as gateway). Connection can be accomplished via SSH to 10.0.0.1, with default
user `usbarmory` and password `usbarmory`. NOTE: There is a DHCP server running
by default. Alternatively the host interface IP address can be statically set
to 10.0.0.2/24.

## Debug accessory
Once the debug accessory is connected, use the following to view serial console
```
picocom -b 115200 -eb /dev/ttyUSB2 --imap lfcrlf
```

## LED feedback

To aid initial testing the base image configures the board LED to reflect CPU
load average, via the Linux Heartbeat Trigger driver. In case this is
undesired, the heartbeat can be disabled by removing the `ledtrig_heartbeat`
module in `/etc/modules`. More information about LED control
[here](https://github.com/f-secure-foundry/usbarmory/wiki/GPIOs#led-control).

## Resizing

The default image is 4GB of size, to use the full microSD/eMMC space a new partition
can be added or the existing one can be resized as described in the USB armory
[FAQ](https://github.com/f-secure-foundry/usbarmory/wiki/Frequently-Asked-Questions-(FAQ)).

## Additional resources

[Project page](https://foundry.f-secure.com/usbarmory)  
[Documentation](https://github.com/f-secure-foundry/usbarmory/wiki)  
[Board schematics, layout and support files](https://github.com/f-secure-foundry/usbarmory)  
[Discussion group](https://groups.google.com/d/forum/usbarmory)  
