---
layout: post
title: "FreeBSD: Creating a Robust OpenVPN Configuration in a Jail"
date: 2026-03-11 13:30:00
---
I recently found myself wanting to run a BitTorrent client behind a VPN and from
within a FreeBSD jail; however, I found no definitive source containing all the
particulars required for this type of setup. I've decided to write this short
guide to summarize my findings and to consolidate the procedure that I
ultimately pieced together. While it has done me well thus far, I make no
guarantees that this will work on your system, nor that it's secure enough for
your needs. This was tested on version 15.0-RELEASE-p4 and with AirVPN as my VPN
service provider. If you have any questions or suggestions, do not hesitate to
reach out--my inbox is always open.

For security's sake, we'll start by creating a thick VNET jail on the host. In
addition to the isolation provided by a thick jail, a VNET jail has the added
benefit of possesing its own network stack separate from the host. Execute the
following commands to download the FreeBSD userland (in this case version 15),
extract it into the jail's directory, copy the timezone and DNS server files
from the host, and update the userland to the latest patch level:

```
# fetch https://download.freebsd.org/ftp/releases/amd64/amd64/15.0-RELEASE/base.txz -o /usr/local/jails/media/15.0-RELEASE-base.txz
# mkdir -p /usr/local/jails/containers/myjail
# tar -xf /usr/local/jails/media/15.0-RELEASE-base.txz -C /usr/local/jails/containers/myjail --unlink
# cp /etc/resolv.conf /usr/local/jails/containers/myjail/etc/resolv.conf
# cp /etc/localtime /usr/local/jails/containers/myjail/etc/localtime
# freebsd-update -b /usr/local/jails/containers/myjail/ fetch install
```

Before continuing with configuring the jail, we first need to prepare our host's
networking configuration. What we intend to do is to bridge two network
segments: our LAN (via the host's Ethernet/IEEE 802.11 network interface) and
our jail's virtual network stack (via the `epair0b` virtual Ethernet interface).
The interface topology presented in the diagram below shows what our system will
look like when the jail is running. On the host, all networked user processes
will use the `bridge0` interface. When the jail is started, we'll create an
`epair(4)`, connecting one interface to the bridge and exposing the other end to
the jail's networking stack.

```
        +-----------------------+
        | Host                  |
        |      +-----------+    |
LAN <---+------> em0/wlan0 |    |
        |      +-----^-----+    |
        |            |          |
        |            |          |
        |       +----v----+     |
        |       | bridge0 |     |
        |       +----^----+     |
        |            | epair0a  |
        |            |          |
        |            |          |
        |            |          |
        |            | +------+ |
        |    epair0b +-> Jail | |
        |              +------+ |
        +-----------------------+
```

Add the following line to your __/etc/rc.conf__ file, replacing `<net_if>` with
the network interface you wish to send traffic over from the jail (e.g., `em0`,
`wlan0`, `lagg0`, etc.):

```
ifconfig_bridge0="addm <net_if> up DHCP"
```

If DHCP is not desired or is unsupported by your router/gateway then you'll
instead need to specify the IP address that will get assigned to `bridge0`
(e.g., `ifconfig_bridge0="inet 192.168.1.2/24 addm <net_if> up"`). If you
already have the `cloned_interfaces` variable defined in your __/etc/rc.conf__
file, append the bridge interface `bridge0` to the value string. If not, then
add the line-enrty `cloned_interfaces="bridge0"`.

With that out of the way, we'll need to provide a configuration file that
specifies how the `jail(8)` utility should manage our newly created jail. Copy
the contents of the following code block into __/etc/jail.conf__. Should you
choose to use a static IP address for the jail-end `epair` interface, replace
the value assigned to `$id` with an unused host identifier on your subnet.

```
myjail {
  # LOGGING
  exec.consolelog = "/var/log/jail_console_${name}.log";

  # PERMISSIONS
  allow.raw_sockets;
  exec.clean;
  mount.devfs;
  devfs_ruleset = 11;

  # PATH/HOSTNAME
  path = "/usr/local/jails/containers/${name}";
  host.hostname = "${name}.local.net";

  # VNET/VIMAGE
  vnet;
  vnet.interface = "${epair}b";

  # NETWORKS/INTERFACES
  $id = "0"; 
  # Uncomment if a static IP is to be used
  #$ip = "10.0.0.${id}/24";
  #$gateway = "10.0.0.1";
  $bridge = "bridge0"; 
  $epair = "epair${id}";

  # ADD TO bridge INTERFACE
  exec.prestart  = "/sbin/ifconfig ${epair} create up";
  exec.prestart += "/sbin/ifconfig ${epair}a up descr jail:${name}";
  exec.prestart += "/sbin/ifconfig ${bridge} addm ${epair}a up";

  # STARTUP/SHUTDOWN
  # Uncomment if a static IP is to be used
  #exec.start    += "/sbin/ifconfig ${epair}b ${ip} up";
  #exec.start    += "echo 'nameserver 8.8.8.8' > /etc/resolv.conf";
  #exec.start    += "/sbin/route add default ${gateway}";
  exec.start	+= "/bin/sh /etc/rc";
  exec.stop	= "/bin/sh /etc/rc.shutdown";

  # REMOVE FROM bridge INTERFACE
  exec.poststop = "/sbin/ifconfig ${bridge} deletem ${epair}a";
  exec.poststop += "/sbin/ifconfig ${epair}a destroy";
}
```

You may have noticed that the value we've assigned to the `devfs_ruleset`
parameter is a ruleset number that does not exist in
__/etc/defaults/devfs.rules__.  This is intentional, and is due to our jail
requiring both `tun` and `pf` control devices to be unhidden in its device file
system. As such, we'll need need to add the following ruleset to
__/etc/devfs.rules__:

```
[devfsrules_jail_vnet_ovpn=11]
add include $devfsrules_jail_vnet
add path tun0 unhide
add path pf unhide
```

The final piece of configuration required on our host is to enable the firewall
(PF). Ensure that its kernel module is loaded (if `kldstat | grep pf` comes back
empty, run `kldload pf`), then add `pf_enable="yes"` and
`pflog_enable="yes"` to __/etc/rc.conf__.

Let's now start up the jail by executing `service jail onestart myjail` and then
enter it with `jexec -u root myjail`. If you now run `ifconfig` you should see
the `epair.*b` interface present. First, install OpenVPN by running `pkg install
openvpn`. We'll then begin our jail configuration by populating __/etc/rc.conf__
with the following three lines:

```
openvpn_enable="YES"
pf_enable="yes"
pflog_enable="yes"
```

If you've chosen to use DHCP for the jail-end interface of the `epair` (that is,
you've left the "static IP" portions of __/etc/jail.conf__ commented out), then
you'll also need to add the line-entry `ifconfig_DEFAULT="SYNCDHCP"` to
__/etc/rc.conf__.

The next step is to configure our firewall. The goal of the firewall is simple:
force all network traffic over our encrypted OpenVPN tunnel. This, however,
presents a conundrum wherein blocking all non-VPN traffic will prevent the jail
from establishing a connection with the VPN server in the first place, since an
initial DNS resolution of the VPN server's hostname is necessary to determine
where we're trying to begin the OpenVPN negotiation with. And of course having a
static rule to pass all traffic to our default DNS runs the risk of leaking IP
addresses of interest to our ISP. Clearly, a static firewall configuration is
insufficient for our needs--a dynamic approach is instead required. Therefore,
startup of the firewall must be done in two phases: in the first phase our
firewall is lax enough to only allow DNS queries to pass through our external
interface (`epair.*b`); in the second phase a startup script will resolve the
VPN server's IP address, record it to bootstrap the subsequent startup of
OpenVPN, and then tighten down the firewall rules to prevent DNS leaks. This is
achieved by the code block below, which should be copied to __/etc/pf.conf__. If
using a static IP address, remember to update the `ext_if` variable.

```
#       $OpenBSD: pf.conf,v 1.34 2007/02/24 19:30:59 millert Exp $
#
# See pf.conf(5) and /usr/share/examples/pf for syntax and examples.
# Remember to set gateway_enable="YES" and/or ipv6_gateway_enable="YES"
# in /etc/rc.conf if packets are to be forwarded between interfaces.

# MACROS
ext_if = "epair0b"
vpn_if = "tun0"

# Set to whatever is required for your OpenVPN config
vpn_server_proto = "udp"
vpn_server_port = "443"

# TABLES
# Table to hold VPN server's entry-IP address. Will be dynamically updated by
# the resolver script when the hostname is resolved
table <vpn_server_ip> persist

# OPTIONS
set skip on lo
set state-policy if-bound

# TRAFFIC NORMALIZATION
scrub in all

# Default packet denial
block all

# Revisit this later
block quick inet6 all

# Allow DHCP on ext_if
pass in quick on $ext_if proto udp from port 67 to port 68 keep state
pass out quick on $ext_if proto udp from port 68 to port 67 keep state

# Only allow traffic on ext_if that is destined to the VPN server (i.e., allow
# only the traffic associated with establishing the OpenVPN tunnel to pass out
# on ext_if)
pass quick on $ext_if inet proto $vpn_server_proto to <vpn_server_ip> port $vpn_server_port keep state

# Initially, allow for traffic destined to any DNS to pass through ext_if. This
# anchor will be dynamically updated (filter ruleset deleted) after the
# vpn_server_ip table is populated by the /usr/local/etc/rc.d/vpn_bootstrap
# startup script
anchor "bootstrap" {
  pass out quick on $ext_if proto { udp, tcp } to any port 53 keep state
}

# Hard block anything else on ext_if
block quick on $ext_if all

pass on $vpn_if inet all keep state
```

Take note of both the table, `<vpn_server_ip>`, and the anchor, `"bootstrap"`;
these will be updated dynamically from our startup script. Create the file
__/usr/local/etc/rc.d/vpn_bootstrap__ and populate it with the following:

```
#!/bin/sh

# PROVIDE: vpn_bootstrap
# REQUIRE: NETWORKING
# BEFORE:  openvpn
# KEYWORD: shutdown

. /etc/rc.subr

name="vpn_bootstrap"
rcvar=vpn_bootstrap_enable

start_cmd="${name}_start"
stop_cmd=":"

load_rc_config $name
: ${vpn_bootstrap_enable:=no}
: ${vpn_bootstrap_host}

vpn_bootstrap_start()
{
        # Attempt to resolve the VPN server's hostname
        ip=$(host "$vpn_bootstrap_host" | cut -w -f 4)
        if [ $? -eq 0 ]; then
                # Add the resolved IP address to the firewall's vpn_server_ip
                # table (/etc/pf.conf)
                pfctl -t vpn_server_ip -T add $ip

                # Attempt to locate the VPN server's address/hostname alias
                # pair in /etc/hosts
                match=$(grep $vpn_bootstrap_host /etc/hosts)
                if [ -z "$match" ]; then
                        # Add the entry if not already present
                        echo "$ip $vpn_bootstrap_host" >> /etc/hosts
                else
                        # Update the entry in case the server's IP address has
                        # been rotated
                        sed -i '' -e "/$vpn_bootstrap_host/c\\
$ip $vpn_bootstrap_host
                        " /etc/hosts
                fi
        else
                echo "Failed to resolve hostname \"$vpn_bootstrap_host\""
        fi

        # Regardless of whether or not the VPN server's hostname can be
        # resolved, delete the rule contained in the firewall's bootstrap
        # anchor since it effectively permits DNS leaks
        pfctl -a bootstrap -F rules
}

run_rc_command "$1"
```

Make it executable by running `chmod +x /usr/local/etc/rc.d/vpn_bootstrap`. The
script is straightforward: while under the default firewall configuration (i.e.,
while any DNS traffic is allowed over our `epair.*b` interface) we first try to
resolve our VPN DNS hostname, add the resolved IP address to the firewall's
`<vpn_server_ip>` table, create a hostname alias for said IP address in
__/etc/hosts__, and finally remove the ruleset in the `"bootstrap"` anchor to
block all non-VPN traffic on the `epair.*b` interface. The reason for adding the
alias entry to __/etc/hosts__ is to give the OpenVPN daemon the ability to
resolve our VPN DNS hostname after the script completes and the firewall becomes
more restrictive. In order for the script to run at startup, we must add the
following two lines to our rc.conf:

```
vpn_bootstrap_enable="yes"
vpn_bootstrap_host="dns.myvpnserver.com"
```

Return to the host by running `exit` and stop the jail with `service jail
onestop myjail`. Go ahead and download an OpenVPN configuration file from your
VPN provider, ensuring that it contains the following three lines:

```
script-security 2
up /usr/local/libexec/openvpn-client.up
down /usr/local/libexec/openvpn-client.down
```

We can then move this file to the correct location in the jail, along with the
supporting up/down scripts for handling DNS pushes from the VPN server:

```
# mkdir /usr/local/jails/containers/myjail/usr/local/etc/openvpn
# mv my_ovpn.conf /usr/local/jails/containers/thick/usr/local/etc/openvpn/openvpn.conf
# mkdir -p /usr/local/jails/containers/thick/usr/local/libexec
# cp /usr/local/libexec/openvpn-client.up /usr/local/jails/containers/thick/usr/local/libexec
# cp /usr/local/libexec/openvpn-client.down /usr/local/jails/containers/thick/usr/local/libexec
```

We're now good to go. Restart and reenter the jail, then run `ifconfig` to
confirm that both `epair.*b` and `tun0` interfaces are present (each should have
a unique IP address). We'll also want to check the contents of __/etc/hosts__ to
make sure that our hostname alias is present at the bottom of the file. As an
additional security measure, we can use a third-party service to check what our
internet-facing IP address is. Execute the following three commands:

```
# pkg install curl
# printf '#!/bin/sh\ncurl --write-out "\\n" https://ipv4.ipleak.net/json/' > leaktest.sh
# chmod +x leaktest.sh
```

Get into the habit of running `./leaktest.sh` when entering the jail or before
initiating internet activity to verify that the jail is indeed routing DNS
traffic to your VPN and not your ISP.
