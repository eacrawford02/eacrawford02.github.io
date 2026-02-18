---
title: System Recovery Instructions
layout: page
---
Please read each step fully before executing the command(s) contained within it.

1. Boot into a clean install of FreeBSD configured with a root-on-ZFS filesystem
and log in as the root user. This step assumes that you have read chapter 2 of
the FreeBSD handbook[1] in its entirety, or are otherwise familiar with POSIX
systems. Feel free to use any arbitrary password for section 2.8.1 of that
chapter.

2. ???Destroy the current root dataset (it will be replaced by the backup and
cannot exist when performing a `zfs receive` operation):

	```
	zfs destroy -Rfnv zroot/ROOT/default
	```

2. Make the directory that will store the key for our encrypted filesystem:

	```
	mkdir /home/.zfskeys
	```

3. Place the secret passphrase in a file under the key directory. Type in the
secret passphrase exactly as it has been provided, placing it between the double
quotes in the below command (replace `<secret_passphrase>` with the passphrase;
the '<' and '>' characters should no longer be present between the double quotes
when the command is run).

	```
	printf "<secret_passphrase>" > /home/.zfskeys/eac
	```

4. Compute the SHA-512 hash of the master passphrase:

	```
	sha512 /home/.zfskeys/eac
	```
    Keep the output of this command on hand: it will be required for steps 5 and
    6\.

5. Restore the backed up system data, replacing "YYYY", "MM", and "DD" with the
date of the last known good backup[2]. If the last known good backup falls on
the first of the month, replace "daily" with "monthly" (e.g.,
`zbackups/ROOT/default@daily_YYYY-MM-01` would become
`zbackups/ROOT/default_cache@monthly_YYYY-MM-01`). If the last known good backup
falls in the previous month, add the "\_cache" suffix to "default" (e.g.,
`zbackups/ROOT/default@daily_YYYY-MM-DD` would become
`zbackups/ROOT/default_cache@daily_YYYY-MM-DD`).

	```
	ssh eac@eac.zfs.rent "zfs send -vw -R zbackups/ROOT/default@daily_YYYY-MM-DD" | zfs receive -vF -d -o canmount=on zroot
	```

    The `ssh` command will prompt you for a password. Enter all characters of
    the SHA-512 hash computed previously. Note that there is no way to copy and
    paste the hash into the SSH command; it must be typed out manually, so do
    excersise diligence when entering it.

6. Restore the backed up user data, following the rules outlined in step 5
(substituting "default" with "eac"):

	```
	ssh eac@eac.zfs.rent "zfs send -vw -R zbackups/home/eac@daily_YYYY-MM-DD" | zfs receive -vF -d -o canmount=on zroot
	```

7. Reboot the system:

	```
	shutdown -r now
	```
    Login as the root user, but this time use the administrator password that
    has been provided to you.

8. Reinstall all packages contained in the package database:

	```
	pkg upgrade
	```

You should now have a working system with all data, configurations, and software
installations restored from the backup. Going forward you can use the provided
administrator password to login to both root and eac users.

[1] [https://docs.freebsd.org/en/books/handbook/bsdinstall/](https://docs.freebsd.org/en/books/handbook/bsdinstall/)

[2] As long as the original system is running, backups are taken at daily
intervals. The last known good backup would therefore be from the date that the
system was last known to be powered and running. If this cannot be determined,
SSH into the remote server and manually inspect all backups by running the
command `zfs list -t snapshot`. Note that backups from the month before last
cannot be recovered.
