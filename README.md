QEMU+KVM VM Provisioning
========================

This is a simple tool that makes it easy to quickly create new Linux and FreeBSD server VMs, running under QEMU+KVM, based on various distribution cloud images. I use this for quick, usually throw-away VMs, when I need to test something in a clean environment, check how a particular different distro does something, test a command or software without affecting my host system, etc.

The script will gather some basic details for the VM, download the requested distribution if necessary, and create cloud-init metadata to configure the network and initial user. The VM will be ready to run with a startup script produced by this tool.

[![Distribution selection](screenshots/page1-thumbnail.png?raw=true)](screenshots/page1.png?raw=true)
[![VM options form](screenshots/page2-thumbnail.png?raw=true)](screenshots/page2.png?raw=true)

A [demonstration and introduction video](https://www.youtube.com/watch?v=jxItb7iZyR0) is available.

Requirements
------------

This script is for Linux systems on x86_64 with virtualization support. The Linux kernel hypervisor, KVM, must be available for the VMs to start.

The script requires a number of utilities: curl, dialog, hexdump, cloud-localds, and, of course, qemu. If any necessary commands are missing, the script will suggest the correct package to install to get them for a number of different distribution/package manager types.

Quick Start
-----------

 1. Clone this repository: `git clone https://github.com/racingmars/vm-provision.git`
 2. Change into the vm-provision directory: `cd vm-provision`
 3. Run the create.sh script and answer the questions: `./create.sh`
 4. Change into the newly created VM directory, which is named with the hostname you provided: `cd vms/<hostname>`.
 5. Start the VM with the start script: `./start-<hostname>.sh`
 6. After a few seconds, you should be able to ssh to the VM using the username, IP address, and SSH key you configured during creation: `ssh -i <public_key_path> <username>@<ip_address>`

Networking -- what's this bridge interface thing?
-------------------------------------------------

I used bridged networking for all of my virtual machines, system emulators, etc. There are lots of different ways to network virtual machines, but this script supports the one method I use 100% of the time, bridging. A full tutorial on setting up a bridge interface with your real network interface is beyond the scope of this project, but here are some hints to point you in the right direction.

On a system with an ethernet interface named `eno1`, for example, we want to move its network configuration over to a new bridge interface named `br0` and then attach `eno1` to the bridge. Our VMs will also connect to `br0` and both our physical host system and our virtual machines will have full network connectivity to each other and the rest of our network.

How you set this up will vary based on your Linux distribution and network manager. You will usually want to make sure the `brctl` command is available; this is provided by a package named bridge-utils on most distributions.

**systemd-network systems**

The network configuration files for systemd-network are in `/etc/systemd/network`. I have a file named `20-wired.network` which attaches my physical wired interface to the bridge:

```
[Match]
Name=eno1

[Network]
Bridge=br0
```

Then I have a file called `br0.netdev` that creates the bridge:

```
[NetDev]
Name=br0
Kind=bridge
```

Finally, the interface configuration that was normally for `eno1` is moved over to the bridge interface itself, which is where the host system's IP stack runs. This is in the file `br0.network`:

```
[Match]
Name=br0

[Network]
Address=192.168.42.8/24
Gateway=192.168.42.1
DNS=192.168.42.5
DNS=192.168.42.2
```

Restart and `brctl show` should show the new `br0` bridge with your existing `eno1` network interface attached.

**Debian systems**

On Debian systems using their wonderful `interfaces(5)` configuration file, you can accomplish all of the configuration in a single file.

For the same configuration described above in the systemd-network systems example, the `/etc/network/interfaces` file on Debian would look like:

```
# The loopback network interface
auto lo
iface lo inet loopback

# Primary physical interface
iface eno1 inet manual

# Primary network interface - bridge
auto br0
iface br0 inet static
    bridge_ports eno1
    address 192.168.42.8/24
    gateway 192.168.42.1
    dns-nameservers 192.168.42.5 192.168.42.2
```

**Other systems**

If you're using other network configuration systems, you'll need to search online for instructions on creating the bridge interface and attaching your physical interface to it.

To root or not to root
----------------------

You can run the VM start script as root, but that's unnecessary: the only special permissions required to start the VM are being able to use the KVM device at /dev/kvm, and being able to create a new network interface bridged to the br0 (or whatever you called it) bridge.

For KVM, many Linux distributions are pre-configured with a group named "kvm" that has permission to use KVM. If your user is in the "kvm" group, you should be able to use kvm. (Do `ls -l /dev/kvm` and see which group is set on the device, and if the permissions include read and write for that group).

For the bridge network configuration, qemu includes a utility called qemu-bridge-helper. You can set this utility to suid root, and create a configuration file that tells it which bridge(s) regular users are allowed to attach to. Different distros install qemu-bridge-helper in different places, so you can find it with `find /usr -name qemu-bridge-helper`. Once you locate it, ensure it's set to suid root if necessary with `sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper` (substituting the path as necessary).

Then create a file at `/etc/qemu/bridge.conf` with the following contents:

```
allow br0
```

That's it! Now regular users will be able to start qemu VMs that attach their network interfaces to your bridge, and therefore to your real physical network.

On a multi-user system, you might not want this. You are responsible for the security and configuration of your system: make choices that reflect your own requirements.

Console / qemu monitor access
-----------------------------

While not typically needed, the system's serial console and the qemu monitor are accessible via Unix sockets that are created when the VM starts. In the VM's directory, they are named _hostname_-serial for the serial console, and _hostname_-mon for the qemu monitor. I recommend connecting to them with the socat utility:

```
socat STDIN,rawer,escape=0x1E unix-connect:hostname-serial
```

The 0x1E escape character is Ctrl-^.

Note that you will not be able to log in to the machine's console until you set passwords on at least one user. The only way to connect to a new VM is with your SSH key via SSH.

Non-interactive / scripted use
------------------------------

To generate virtual machines without the dialog interface (e.g. from a script), you may set environment variables.

Set the following variables to inhibit display of the distribution selection dialog.

 - `VM_PROVISION_BASEIMG`: The filename (in the "images" directory) of the QCOW2 disk image file on which to base the new VM. If the file already exists, it will be used. If the file does not exist, `VM_PROVISION_BASEIMG_URL` *must* be set and contain the URL from which to download the image file.
 - `VM_PROVISION_BASEIMG_URL`: The URL from which to download the base image for the new virtual machine. If the file named by the `VM_PROVISION_BASEIMG` variable exists in the "images" directory, this variable is optional and will not be used.

Set the following variables to inhibit display of the options dialog. If only a subset of the following variables are set, the options dialog will be displayed with the provided values as defaults.

 - `VM_PROVISION_HOSTNAME`: The hostname for the new VM.
 - `VM_PROVISION_DOMAIN`: The domain name for the new VM.
 - `VM_PROVISION_IP`: The IP address and CIDR netmask for the new VM (e.g. 192.168.32.18/24).
 - `VM_PROVISION_GW`: The IP address of the default gateway.
 - `VM_PROVISION_DNS`: Space-delimited list of DNS server IP addresses.
 - `VM_PROVISION_BRIDGE`: The interface name (e.g. br0) of the network bridge interface to connect the new VM to.
 - `VM_PROVISION_USER`: The username to create in the new VM.
 - `VM_PROVISION_PUBKEY`: Path to a file containing the SSH public key for the user.
 - `VM_PROVISION_RAM`: Size, in megabytes, of the new VM's memory.
 - `VM_PROVISION_DISK`: Size, in gigabytes, of the new VM's hard disk.

If there are validation errors, the dialog interface will still be displayed and will wait for input.

License
-------

Copyright 2023 Matthew R. Wilson <mwilson@mattwilson.org>

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.

