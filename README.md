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

## Build Modes
Enable LUKS with secure boot requires a lot of work manually, I have came up with an easy way to provision the drives without the need to use debug cables or doing manual file updates on the SD card (debug cable is still highly recommended).

The following build mode can be chosen with this script:

* Normal (no need to supply PKI)
* Signed (PKI and public key for bootloader needs to be provided for secure boot)

## LUKS Mode
If you want to build LUKS encrypted image, please set `LUKS=on` when running make.

If LUKS is turned on, the auto unlock script will be added with an random password. (This is not safe, you must rebuild boot partition with derived password later)

### LUKS KDF
By default LUKS2 uses Argon2i as KDF (key derivation function), the problem with it is since the parameters is calculated during a benchmark for `luksFormat` if you execute this Makefile (which I believe you would) on a way faster machine, the resulting LUKS partition will take ages to unlock due to the complexity of the KDF. There is two way to fix this:
* Run `luksFormat` on device so the resulting partition is somewhat usable
* Tweak the Argon2i's parameters so it doesn't matter if you create it on a faster machine or slower machine.

Note, because the script is tweaking the default parameters for LUKS, it might decrease security for the resulting partition. Just keep this in mind.

## Build Target
* boot partition (used to update kernel, provision new key)
* bootloader (used to update bootloader)
* full image (full image that can be written to the SD)

## Secure Boot Procedure
To enable secure boot with LUKS encrypted rootfs, please follow the following procedure:

### Locked Devices
If your devices is already locked down, SoC fused, you can only use `Signed Mode`, any unsigned bootloader will not able to run on the device. But you can still use this script if you have the PKI keys and build in signed mode.

1. Build LUKS enabled signed image
2. Login and run `dcp_derive enc [new key] [diversifier]` and get the hardware derived key. Copy this.
3. Rebuild the boot partition with PKI and `[derived key]` and `[diversifier]`
4. Flash the new boot partition.

### Unlocked Devices
If your devices is unlocked, you can execute unsigned image, but I do recommend you put the device in locked state after

1. Build LUKS enabled unsigned image
2. Login and run `dcp_derive enc [new key] [diversifier]` and get the hardware derived key. Copy this.
3. Rebuild the boot partition with `[derived key]` and `[diversifier]`
4. Flash the new boot partition.
5. Test to see if unlock works
6. Generate the PKI and fust the SoC
7. Rebuild the boot partition with PKI and `[derived key]` and `[diversifier]`
8. Flash the new boot partition.## Pre-requisites

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

## Building signed image
If your device is already fused or you want to use signed image before you fuse the keys, you can build with signed target. Make sure you mount the folder including your HAB keys and armory-boot public/private keys to the docker container.
```
docker run --rm -it --privileged -v $(pwd):/opt/armory -v /home/mykeys:/opt/pki-keys --name armory armory
```

**The makefile will default using /opt/pki-keys, but you can override that setting.**

The you can build the target with:
```
make IMX=imx6ulz BOOT=uSD SIGNED=on ....BOOT_PRIVATE_KEY=xxxxx
```

### Relevant parameters

* BOOT_PRIVATE_KEY_PASSWORD (the private key password, if not provided, it will be prompted)
* BOOT_PRIVATE_KEY (the private key file location, default to /opt/pki-keys/armory-boot.asc)
* BOOT_PUBLIC_KEY (the last line of the public key, not file name)
* HAB_KEYS (the location of the HAB keys, folder containing all the keys generated by habtool https://github.com/f-secure-foundry/usbarmory/wiki/Secure-boot-(Mk-II))

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

## LUKS resize
After install and confirming the image works on your device, you might want to extend the LUKS partition to fill the rest of your storage device, you can follow the guide here:
https://unix.stackexchange.com/questions/320957/extend-a-luks-encrypted-partition-to-fill-disk

```
sudo parted /dev/sdX (your sd card)
> resizepart 2 100%
> q

sudo cryptsetup resize [mapper name]

sudo e2fsck -f /dev/mapper/[mapper name]
sudo resize2fs /dev/mapper/[mapper name]
```

## Bootup sequence
During the boot sequence, various LED will be lit up indicating the stage of the boot sequence. The boot will come in two stages for secure boot with LUKS.

1. Secure Boot
2. LUKS Unlock

Here are the LED sequence to look for if you do not have an debug cable or console is turned off on your device.

### Secure Boot (armory-boot)

| Boot sequence                   | Blue | White |
|---------------------------------|------|-------|
| 0. initialization               | off  | off   |
| 1. boot media detected          | on   | off   |
| 2. kernel verification complete | on   | on    |
| 3. jumping to kernel image      | off  | off   |

### LUKS Unlock

| Unlock sequence                 | Blue | White |
|---------------------------------|------|-------|
| 0. kernel module loaded         | off  | on    |
| 1. before LUKS unlock           | on   | on    |
| 2. LUKS unlocked                | off  | on    |
| 3. before calling switch_root   | off  | off   |

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
