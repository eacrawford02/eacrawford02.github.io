---
title: System Recovery Instructions
layout: page
---
Please read each step fully before executing the command(s) contained within it.

1. Perform a clean install of FreeBSD configured with a root-on-ZFS filesystem.
This step assumes that you have read chapter 2 of the FreeBSD handbook[1] in its
entirety, or are otherwise familiar with POSIX systems. Feel free to use any
arbitrary password for section 2.8.1 of that chapter.

2. Reboot into the same installation media used for Step 1. At the installer
welcome menu, select the Live CD option (for reference, see section 2.10 of the
handbook). Sign in as the root user by entering `root` at the prompt, followed
by an empty password.

3. Connect to the internet. Start by running the following command:
   ```
   echo "nameserver 8.8.8.8" > /tmp/bsdinstall_etc/resolv.conf
   ```
   For a wired connection, first identify the Ethernet interface by running
   `ifconfig` (if the output of this command looks unfamiliar, a detailed
   description can be found in section 7.3 of the handbook). Then, configure
   DCHP for that interface:
   ```
   dhclient <interface>
   ```
   Test the connection by running `ping -c 4 8.8.8.8`.

4. __Optional__ - Install the `mbuffer` software tool to optimize the download
of backups in later steps. Doing so should provide significant time savings. Run
the following six commands in sequence:
   ```
   mount -o size=500M -t tmpfs tmpfs /usr/local
   export TMPDIR=/usr/local
   export PKG_DBDIR=/usr/local/db/pkg
   export PKG_CACHEDIR=/usr/local/cache/pkg
   pkg bootstrap -f
   pkg install mbuffer
   ```

5. Place the secret passphrase in a key file. Type in the secret passphrase
exactly as it has been provided, placing it between the double quotes in the
below command (replace `<secret_passphrase>` with the passphrase; the '<' and
'>' characters should no longer be present between the double quotes when the
command is run).
   ```
   printf "<secret_passphrase>" > /tmp/key
   ```

6. Compute the SHA-512 hash of the master passphrase:
   ```
   sha512 /home/.zfskeys/eac
   ```
   Keep the output of this command on hand: it will be required for steps 7 and
   11\.

7. Restore the backed up system data, replacing "YYYY", "MM", and "DD" with the
date of the last known good backup[2]. If the last known good backup falls on
the first of the month, replace "daily" with "monthly" (e.g.,
`zbackups/ROOT/default@daily_YYYY-MM-01` would become
`zbackups/ROOT/default_cache@monthly_YYYY-MM-01`). If the last known good backup
falls in the previous month, add the "\_cache" suffix to "default" (e.g.,
`zbackups/ROOT/default@daily_YYYY-MM-DD` would become
`zbackups/ROOT/default_cache@daily_YYYY-MM-DD`).
   ```
   ssh eac@eac.zfs.rent 'zfs send -vwb -R zbackups/ROOT/default@daily_YYYY-MM-DD' | zfs receive -vuF -d zroot
   ```
   __If you optionally followed Step 4__, run the following command instead.
   ```
   ssh eac@eac.zfs.rent 'zfs send -vwb -R zbackups/ROOT/default@daily_YYYY-MM-DD | mbuffer -s 128k -m 1G 2>/dev/null' | mbuffer -s 128k -m 1G 2>/dev/null | zfs receive -vuF -d zroot
   ```
   The `ssh` command will prompt you for a password. Enter all characters of
   the SHA-512 hash computed previously. Note that there is no way to copy and
   paste the hash into the SSH command; it must be typed out manually, so do
   excersise diligence when entering it.

8. Mount the root dataset:
   ```
   zpool import -R /mnt zroot
   ```

9. Make the directory that will store the key for our encrypted filesystem and
populate it with the previously created key file:
   ```
   mkdir /mnt/home/.zfskeys
   mv /tmp/key /mnt/home/.zfskeys/eac
   ```

10. Unmount the root dataset:
    ```
    zfs unmount -a
    ```

11. Restore the backed up user data, following the rules outlined in Step 5
(substituting usage of "default" in those rules with "eac"):
    ```
    ssh eac@eac.zfs.rent 'zfs send -vwb -R zbackups/home/eac@daily_YYYY-MM-DD' | zfs receive -vuF -d zroot
    ```
    Again, __if you optionally followed Step 4__, run the following command
    instead.
    ```
    ssh eac@eac.zfs.rent 'zfs send -vwb -R zbackups/home/eac@daily_YYYY-MM-DD | mbuffer -s 128k -m 1G 2>/dev/null' | mbuffer -s 128k -m 1G 2>/dev/null | zfs receive -vuF -d zroot
    ```

12. Reboot the system:
    ```
    shutdown -r now
    ```

You should now have a working system with all data, configurations, and software
installations restored from the backup. Going forward you can use the provided
administrator password to login to both root and eac users. After booting into
the OS, and before logging in as the user eac, entering the key chord Alt-F2
will cause the system to launch the desktop GUI upon successful sign-in. In this
mode, a terminal can be opened via the Win+Enter key chord.

[1] [https://docs.freebsd.org/en/books/handbook/bsdinstall/](https://docs.freebsd.org/en/books/handbook/bsdinstall/)

[2] As long as the original system is running, backups are taken at daily
intervals. The last known good backup would therefore be from the date that the
system was last known to be powered and running. If this cannot be determined,
SSH into the remote server (run `ssh eac@eac.zfs.rent` and enter the SHA-512
hash when prompted for a password) and manually inspect all backups by running
the command `zfs list -t snapshot`. Note that backups from the month before last
cannot be recovered.
