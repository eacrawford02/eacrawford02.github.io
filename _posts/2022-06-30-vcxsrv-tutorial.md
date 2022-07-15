---
layout: post
title: Running VcXsrv in WSL2 on Windows 10 Securely
date: 2022-06-30 22:16:16
---
So, you'd like to be able to run Linux GUI apps from WSL2. Unfortunately, native support for this feature is restricted to WSLg, which is only available on Windows 11, leaving all of us still stuck on Windows 10 (either by choice or by circumstance) out of luck. There is some good news, though: it's possible to get this to work by using third party tools. Although this method of running GUI apps has existed for quite some time now (predating the introduction of WSLg), it is an error-prone endeavor, with many of the resources online advocating for insecure network setups between WSL2 and the host machine. As such, I decided to put together a simple step-by-step guide for getting an X server, VcXsrv, set up with WSL2 to allow for GUI apps installed in Linux to be displayed on Windows 10, all without compromising the security of your machine.

## 1. Install VcXsrv

Download the VcXsrv program from [https://sourceforge.net/projects/vcxsrv/](https://sourceforge.net/projects/vcxsrv/) and follow the installation wizard.

## 2. Obtain host IP address

We start by obtaining the host IP address. This belongs to the network adapter that allows for the host machine to connect to the internet, the IP address of which can be obtained by running the following command in bash:

```
route.exe print | grep 0.0.0.0 | head -1 | awk '{print $4}'
```

Alternatively, run `ipconfig` from the host machine command prompt and locate the IPv4 address under whatever your built-in network adapter is (i.e., wireless LAN, ethernet, **not** the WSL vEthernet virtual adapter).

We can then export this address as an environment variable for reference in the current session:

```
# ':0' denotes that this is display number 0 (the first)
export DISPLAY=$(route.exe print | grep 0.0.0.0 | head -1 | awk '{print $4}'):0.0
```

This variable will be used to tell an application (on our Linux distro) how to connect to an X server (on our host).

## 3. Install Required Tools

To install the tools required for setting up VcXsrv, run the following three commands in bash:

```
sudo apt install -y xauth coreutils gawk x11-apps # x11-apps contains our test program
touch ~/.Xauthority # Creates .Xauthority file to store display entries (not done by install for whatever reason)
xauth list # Verify installations by printing list of display entries. Should be empty
```

The created .Xauthority file can then be stored in a local environment variable like so:

```
export XAUTHORITY=~/.Xauthority
```

## 4. Configuring Authorization File

With xauth installed, an authorization entry for the selected display can be added to the .Xauthority file. Since communication between the application being displayed and the server displaying it is done over a virtual network interface, other actors (either local or remote) could attempt to establish a connection with the display on the host. To prevent this, the X server allows for an authorization mechanism in the form of a MIT-MAGIC-COOKIE-1. It is the xauth tool that allows us to do perform this authorization with the server. We start by creating a cookie using a secret password in the shell:

```
magiccookie=$(echo '{super-secret-password}'|tr -d '\n\r'|md5sum|gawk '{print $1}')
```

We then associate the cookie with the display (using "." to specify the MIT-MAGIC-COOKIE-1 format) and add it to the authorization file:

```
xauth add "$DISPLAY" . "$magiccookie"
```

To verify that the entry was successfully added, run the same `xauth list` command again--it should print the entry. For more information on the xauth command, refer to [https://www.ibm.com/docs/en/aix/7.2?topic=x-xauth-command](https://www.ibm.com/docs/en/aix/7.2?topic=x-xauth-command).

Now that the .Xauthority authorization file has been edited, we can copy it into the host's UserProfile folder (which we grab using cmd.exe):

```
userprofile=$(wslpath $(/mnt/c/Windows/System32/cmd.exe /C "echo %USERPROFILE%" | tr -d '\r\n'))
cp ~/.Xauthority "$userprofile"
```

To ensure that this was successful, check your userprofile folder (in C:\\Users\\) for the .Xauthority file.

## 5. Export Display on Startup

To export both the display and authorization file environment variables on shell startup, add their respective export command to ~/.bashrc in your Linux distro:

```
echo "export DISPLAY=$(route.exe print | grep 0.0.0.0 | head -1 | awk '{print $4}'):0.0" >> ~/.bashrc
echo "export XAUTHORITY=~/.Xauthority" >> ~/.bashrc
```

To enable hardware acceleration for optimized rendering of WSL2 graphical apps, execute the following bash command:

```
echo "export LIBGL_ALWAYS_INDIRECT=1" >> ~/.bashrc
```

Verify with `tail -3 ~/.bashrc` and have the change take effect in the current shell with `. ~/.bashrc`.

## 6. Create Shortcut to VcXsrv

Back on the host machine, we'll now create a shortcut to VcXsrv.exe with the desired command line arguments. First, navigate to the installation location of VcXsrv.exe (default is "%ProgramFiles%\VcXSrv\VcXSrv.exe") in file explorer. Right click on VcXSrv.exe and select "Create Shortcut" to place a shortcut on the desktop. Right click on the shortcut and select "Properties". In the "Target" field, append the following arguments after the quoted target executable:

```
%ProgramFiles%\VcXsrv\vcxsrv.exe -multiwindow -clipboard -wgl -auth "%USERPROFILE%\.Xauthority"
```

Click ok to save the changes (and feel free to change the shortcut name to something more memorable while you're here). To have the server launch at startup, move the shortcut into the Windows startup folder (default location is "C:\Users\%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"; alternatively, run "shell:startup" from the run command window).

## 7. Configure Windows Firewall

The last step involved in setting up VcXsrv is to allow for traffic from WSL to pass through the firewall. This is necessary because we are communicating with the host via its network interface, so from the host's perspective, this traffic will appear to be coming from another machine on the network. Windows Firewall will block this automatically, so we must create an **inbound rule** to override this. We want to configure this rule for **TCP** traffic over the **specific local port 6000**. To limit the **scope** of the rule (so that only our Linux distro can communicate with the server and not the entire internet--this is *very* important), we'll only allow the remote IP addresses of the subnets used by WSL2. These are "172.16.0.0/12" and "192.168.0.0/16". Note that this should be the only rule associated with VcXsrv; if there other rules are present in the inbound rules list within the firewall (e.g., "VcXsrv windows xserver"), make sure they are disabled. For a detailed walkthrough of setting up the firewall rule, give the following article a read: [https://skeptric.com/wsl2-xserver/](https://skeptric.com/wsl2-xserver/).

## Further Reading

For more information on the details of xauth, please refer to the following resource:
- [https://unix.stackexchange.com/questions/612268/about-xauth-and-display-variable](https://unix.stackexchange.com/questions/612268/about-xauth-and-display-variable)
