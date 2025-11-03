---
layout: post
title: "FreeBSD: Manually Preparing Disks for Root-on-ZFS During Installation"
date: 2025-11-01 15:00:00
---
Earlier this year, I set up a remote VPS running FreeBSD (to be used as an
offsite backup of my local system) and had to go through several iterations of
installing the OS as I worked through mistakes made when performing the manual
disk partitioning and preparation step of the install process. At some point
during that excursion, I thought it wise to write up a guide that I could follow
in subsequent installs. This was tested on FreeBSD 14.2-RELEASE.

Follow the installation wizard until reaching the "Partitioning" section. Select
the "Shell" option to set up a root-on-ZFS system manually using an interactive
shell.

Load the ZFS kernel module:

```
kldload zfs
```

Force 4 KiB sectors (a shift of 12 bits represents 2^12 = 4096 = 4 KiB):

```
sysctl vfs.zfs.min_auto_ashift=12
```

Show all disk-like geoms:

```
geom disk list
```

Create a new partitioning scheme on the desired geom (only if absent; check
first with `gpart show -p <geom>`):

```
gpart create -s GPT <geom>
```

Next, we'll need to add a bootstrap partition and populate it with bootcode
(again, only if absent). There are two options for doing so, depending on
whether the system's motherboard firmware supports UEFI or BIOS (this can be
found by running `sysctl machdep.bootmethod`). In both cases, ensure that the
partitions are 4 kB aligned.

a) For UEFI boot:

```
# EFI partition size should be an even multiple of 1 MB
gpart add -a 4k -s 260M -t efi <geom>
newfs_msdos -F 32 -c 1 /dev/ada0p1
```

The above command following `gpart add` construct a MS-DOS (FAT32) file system on
the created EFI partition.

b) For legacy boot (BIOS):

```
gpart add -a 4k -s 512K -t freebsd-boot <geom>
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 <geom>
```

The `gpart bootcode` command seen above embeds a protective MBR (the
`/boot/pmbr` file) into the first disk sector, and then writes the bootstrap
code (from the file `/boot/gptzfsboot`) to partition index 1. See the
"BOOTSTRAPPING" section of `GPART(8)` for more information.

Add a swap partition (in this case, 4 GB in size):

```
gpart add -a 4k -l swap0 -s 4G -t freebsd-swap <geom>
```

Add a ZFS partition to fill the remaining free space:

```
gpart add -a 4k -l zfs0 -t freebsd-zfs <geom>
```

Verify that the partitioning scheme has been structured correctly by showing the
current partition information:

```
gpart show -p <geom>
```

Note that when the label option (`-l <my_label>`) is supplied to `gpart add`,
the created GPT label will appear in `/dev/gpt`. GPT labels and their associated
partitions can also be vied with `gpart show -l`.

Before proceeding with the set-up of ZFS, it's worth covering the desired
properites of the system we're going to configure, as these will influence the
dataset structure we create. It is generally advisable to separate the bootable
portion of the filesystem (i.e., all data that is required to boot and operate
the OS, including pre-installed software) from the remaining user data and any
transient data. Doing so allows for bootable system image instances to be
created and re-used in the case of system failure or on different machines
altogether. This concept is supported natively in ZFS via boot environments. A
boot environment is simply a bootable dataset that can be mounted as the root
file system at boot time. There can only be one active boot environment for a
pool at any given time.

The default filesystem structure created by the FreeBSD installer is a "shallow"
boot environment, where a boot environment parent dataset is created under the
root of the ZFS filesystem (e.g., `zroot`) and boot environment datasets are
placed under this parent. The boot environment datasets themselves do not have
any directly subordinate datasets (see the "Boot Environment Structures" section
of `BECTL(8)` for more information). This layout is also expected by the `bectl`
tool, so we will adhere to it.

We'll first create a ZFS pool, in this case named "zroot" (a storage pool is
also the root of the ZFS file system hierarchy), containing a single vdev, which
itself consists of a single ZFS disk partition we previously created:

```
zpool create -f -o altroot=/mnt -O compress=lz4 -O atime=off -m none zroot /dev/gpt/zfs0
```

When users opt to perform shell mode partitioning, the FreeBSD installer expects
the filesystem into which the OS will be installed to be mounted under the
`/mnt` directory (this is mentioned in the intial message printed when entering
shell mode). We therefore set the `altroot` property to `/mnt`, which will
prepend this alternate root directory to all mount points within the pool since
child datasets will inherit this property. This is a one-off property and will
not persist past a reboot, so all datasets will be mounted at their specified
mount points post-installation. Some set-up guides may mount a `tmpfs` at `/mnt`
prior to this step; however, this is not necessary if `altroot=/mnt` is
specified.

We also set two file system properties in the root file system of the pool (see
`zfsprops(7)` for more details), which will be inherited by all child datasets.
Of note is the `atime` property, which we disable for both performance and
archival reasons.

We can now begin creating our ZFS filesystem hierarchy, starting with the boot
environment parent dataset:

```
zfs create -o mountpoint=none zroot/ROOT
```

Since `ROOT` is intended to be a parent dataset under which all boot
environment datasets will be created, we make it non-mountable. We can then
follow that by creating the default boot environment:

```
zfs create -o mountpoint=/ zroot/ROOT/default
```

Let's continue with the rest of the hierarchy:

```
zfs create -o mountpoint=/home zroot/home
zfs create -o mountpoint=/usr -o canmount=off zroot/usr
zfs create -o setuid=off zroot/usr/ports
zfs create zroot/usr/src
zfs create -o mountpoint=/var -o canmount=off zroot/var
zfs create -o exec=off -o setuid=off zroot/var/audit
zfs create -o exec=off -o setuid=off zroot/var/crash
zfs create -o exec=off -o setuid=off zroot/var/log
zfs create -o atime=on zroot/var/mail
zfs create -o setuid=off zroot/var/tmp
```

We've introduced a couple new file system properties here, the most important of
which is `canmount=off`. The rationale is twofold:

1. Doing so allows the datasets to be used solely as a mechanism for their
children to inherit properties (namely `mountpoint`) without themselves being
mounted.  This saves us from needing to manually specify the mountpoint for each
child.  The `canmount` property is not inherited so we don't have to worry about
it affecting child datasets.

2. Because these datasets are not mounted, but their mount points are
subdirectories of their parent datasets' mount points (e.g., `/var` is a
subdirectory of `/`), files written to the mount points of these datasets will
instead get placed on their parent datasets and thus will be included in the
boot environment. Furthermore, any child datasets with `canmount` left on will
still get mounted to their mount points, and any files written to that
subdirectory will be excluded from the boot environment. It is therefore a
mechanism to signal that a dataset should be part of the boot environment.

We also disable the execution of processes with `exec=off` in the
`zroot/var/{audit,crash,log}` filesystems for security purposes.

Double check that we've set up the filesystem hierarchy correctly by running:

```
zfs list -o name,canmount,mountpoint
```

Let's set the standard permissions for the `/var/tmp` directory:

```
chmod 1777 /mnt/var/tmp
```

Next, we must configure the root filesystem of the pool as the boot environment
using the `bootfs` pool property. This property is used by the `gptzfsboot`
bootcode that is installed in the `efi`/`freebsd-boot` disk partition.

```
zpool set bootfs=zroot/ROOT/default zroot
```

Enable ZFS in the system configuration file:

```
echo 'zfs_enable="YES"' >> /tmp/bsdinstall_etc/rc.conf
```

With the ZFS set-up out of the way, there are a couple `fstab` entries that must
be added. First, add an `fstab` entry to use a GELI-encrypted swap partition:

```
printf "/dev/gpt/swap0.eli\tnone\tswap\tsw\t0\t0\n" >> /tmp/bsdinstall_etc/fstab
```

Second, add an `fstab` entry to use a `tmpfs` for `/tmp`:

```
printf "tmpfs\t/tmp\ttmpfs\trw,mode=1777\t0\t0\n" >> /tmp/bsdinstall_etc/fstab
```

We can now proceed with the rest of the installation. Enter `exit` to return to
the FreeBSD installer.

Sources (RTFM, baby):

```
man zpool-create
man zfsconcepts
man zpoolprops
man zfs-create
man zfsprops
man bectl
```
