## Light OS - Porteus live USB bootable installer

It creates a bootable USB with 128MB for persistence.

- Porteus root password: **toor**

- Background image source: [Newsweek](https://www.newsweek.com/government-report-new-space-race-nasa-china-1736843)

- Usage: `bash porteus-usb-install.sh /path/file.iso [/dev/]sdx [it] [--ext4-install]`
   - When everything is already local and updated as per the latest ISO.
   - Long option creates a USB bootable installation instead of a LIVE.
   - Performances LIVE vs EXT4 may greatly vary depending on USB stick.
   - First EXT4 installation boot is **slow** because lazy mkfs options.
   - Some USB2 sticks allow legacy boot only, it may be disabled in BIOS.

- Usage: `bash porteus-net-install.sh [<type> <url> <arch> <vers>] [/dev/sdx] [it]`
   - when downloading the ISO and retrieving this repo scripts is needed.

- Usage: `bash porteus-mirror-selection.sh [--clean]`
   - check among the available mirrors the fastest one for downloading.  

The v0.2.0 has been reported that it works also for [PorteuX](https://github.com/porteux/porteux) but I did not test it and I am not granting the compatibility for the future.

---

### Persistence vs Installation

<div align="justify">

> Persistence means that any changes you make to the system (like installing software, saving files, or changing settings) will be saved and available the next time you boot from the USB drive. Without persistence, the system would revert to its original state each time. Installation is a process designed to create a permanent and independent operating environment while a [LIVE](https://en.wikipedia.org/wiki/Live_USB) is running into the computer's RAM, mainly. This allows users to run an OS without modifying the host system's storage. Persistence, is a bridge between the two concepts. &ndash;&nbsp;Gemini&nbsp;2

</div>

To understand the difference between the two variants, the LIVE is the most similar to the original Porteus while the EXT4 allows one to install a system from scratch. The timings of these two examples are referring to Porteus v5.1 (alpha2) an USB 2.0 usbstick 64GB paid €3.11 on Temu:

```
INFO: Creation LIVE usbstick completed in 34 seconds.

Device     Boot   Start     End Sectors  Size Id Type
/dev/sda1  *       2048 2459647 2457600  1.2G  7 HPFS/NTFS/exFAT
/dev/sda2       2459648 3893247 1433600  700M 83 Linux

Filesystem        Size  Used Avail Use% Mounted on
/dev/sda1          16M   13M  3.5M  79% /tmp/usb1
/dev/sda2         1.8G  475M  1.3G  28% /tmp/usb2

INFO: Creation EXT4 usbstick completed in 38 seconds.

Device     Boot   Start     End Sectors  Size Id Type
/dev/sda1  *       2048   34815   32768   16M  7 HPFS/NTFS/exFAT
/dev/sda2         34816 3885055 3850240  1.8G 83 Linux

Filesystem        Size  Used Avail Use% Mounted on
/dev/sda1         1.2G  616M  583M  52% /tmp/usb1
/dev/sda2         672M   28K  623M   1% /tmp/usb2

INFO: boot by EXT4 ubstick, and to proceed with an installation type:

dd if=/dev/sdb bs=1M count=2k of=/dev/sda status=progress oflag=dsync

This will overwrite data on /dev/sda installing a working EXT4 system.
```

In this example the `/dev/sdb` is the usbstick while the `/dev/sda` is the internal storage device which is installed from scratch  (**WARNING**: data loss). For example, writing at 40M/s (USB 2.0) on average, it takes less than a minute for completing the installation.

---
