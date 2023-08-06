#!/bin/sh

###############################################################################
# Automated QEMU Linux VM Creator                                             #
# https://github.com/racingmars/vm-provision                                  #
#                                                                             #
# Copyright 2023 Matthew R. Wilson <mwilson@mattwilson.org>                   #
#                                                                             #
# This program is free software: you can redistribute it and/or modify it     #
# under the terms of the GNU General Public License as published by the Free  #
# Software Foundation, either version 3 of the License, or (at your option)   #
# any later version.                                                          #
#                                                                             #
# This program is distributed in the hope that it will be useful, but WITHOUT #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or       #
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for    #
# more details.                                                               #
#                                                                             #
# You should have received a copy of the GNU General Public License along     #
# with this program. If not, see <https://www.gnu.org/licenses/>.             #
###############################################################################

# tmpfile will hold the answers from our invocations of dialog(1)
tmpfile=$(mktemp)

# We always want to clean up our tmpfile if we exit early with an error, so we
# will use this function whenever we want to bail out.
fatalerror() {
    rm -f "$tmpfile"
    exit 1
}

# printerr is a utilty function to invoke printf with output redirected to
# stderr.
printerr() {
    printf "$@" 1>&2
}

# checkcommand checks if the requested binary, $1, is on the path, and if not,
# prints instructions to install the packagename $2 on debian, $3 on RHEL, and
# $4 on Arch distribution types. Returns zero if found, non-zero otherwise.
checkcommand() {
    if command -v $1 > /dev/null 2>&1; then
        return 0
    fi

    # Command not found, print info
    printerr "\nERROR: The command %s is required but not installed.\n" $1
    printerr "Please use your package manager to install the package:\n"
    printerr "  apt install %s\n" $2
    printerr "  yum [or dnf] install %s\n" $3
    printerr "  pacman -S %s\n" $4

    return 1
}

# checkhw confirms this is an x86_64 system with KVM enabled. If not, print
# an error and exit.
checkhw() {
    if [ $(uname -m) != "x86_64" ]; then
        printerr "\nERROR: This script only supports x86_64 hardware.\n"
        fatalerror
    fi

    if [ ! -e /dev/kvm ]; then
        printerr "\nERROR: KVM does not appear to be active on this system.\n"
        fatalerror
    fi
}

# checkprereqs will check for all of our utility prerequisits at once, so we
# can provide the user a full list of what needs to be installed in one shot.
# If there are missing prerequisites, we will exit.
checkprereqs() {
    needprereq=0

    checkcommand curl curl curl curl
    [ $? -ne 0 ] && needprereq=1

    checkcommand dialog dialog dialog dialog
    [ $? -ne 0 ] && needprereq=1

    # We only need uuidgen if the kernel doesn't give us UUIDs
    if [ ! -e /proc/sys/kernel/random/uuid ]; then
        checkcommand uuidgen uuid-runtime util-linux util-linux
        [ $? -ne 0 ] && needprereq=1
    fi

    checkcommand hexdump bsdextrautils util-linux util-linux
    [ $? -ne 0 ] && needprereq=1

    checkcommand cloud-localds cloud-image-utils cloud-utils cloud-image-utils
    [ $? -ne 0 ] && needprereq=1

    checkcommand qemu-img qemu-utils qemu-img qemu-img
    [ $? -ne 0 ] && needprereq=1

    if [ $needprereq -ne 0 ]; then
        printerr "\nERROR: cannot continue until prerequisites are present.\n"
        fatalerror
    fi
}

# selectdistro presents the dialog menu to choose from common Linux distros
# that provide downloadable cloud images that will work with qemu +
# cloud-init. This will populate the VM_PROVISION_BASEIMG and
# VM_PROVISION_BASEIMG_URL variables.
selectdistro() {
    # Check if we can skip distro selection
    if [ -n "$VM_PROVISION_BASEIMG" ]; then
        if [ -e "images/$VM_PROVISION_BASEIMG" ]; then
            # User has provided the base image via environment variable, and
            # it exists.
            return
        else
            if [ -n "$VM_PROVISION_BASEIMG_URL" ]; then
                # User has provided the download URL.
                return
            fi
        fi
    fi

    dialog --title "Distribution Selection" \
        --menu "Select a Linux distribution for the new VM:" 20 75 14 \
        a 'AlmaLinux 8' \
        b 'AlmaLinux 9' \
        c 'Arch Linux' \
        d 'Debian 11' \
        e 'Debian 12' \
        f 'Fedora 38' \
        g 'openSUSE Leap 15.5' \
        h 'Rocky Linux 8' \
        i 'Rocky Linux 9' \
        j 'Ubuntu 20.04 LTS' \
        k 'Ubuntu 22.04 LTS' \
        l 'Ubuntu 23.04' 2>$tmpfile
    clear

    selection=$(cat $tmpfile)
    
    case "$selection" in
    a)  # AlmaLinux 8
        VM_PROVISION_BASEIMG=AlmaLinux-8-GenericCloud-latest.x86_64.qcow2
        VM_PROVISION_BASEIMG_URL=https://repo.almalinux.org/almalinux/8/cloud/x86_64/images/$VM_PROVISION_BASEIMG
        ;;
    b)  # AlmaLinux 9
        VM_PROVISION_BASEIMG=AlmaLinux-9-GenericCloud-latest.x86_64.qcow2
        VM_PROVISION_BASEIMG_URL=https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/$VM_PROVISION_BASEIMG
        ;;
    c)  # Arch Linux
        VM_PROVISION_BASEIMG=Arch-Linux-x86_64-cloudimg.qcow2
        VM_PROVISION_BASEIMG_URL=https://geo.mirror.pkgbuild.com/images/latest/$VM_PROVISION_BASEIMG
        ;;
    d)  # Debian 11
        VM_PROVISION_BASEIMG=debian-11-genericcloud-amd64.qcow2
        VM_PROVISION_BASEIMG_URL=https://cloud.debian.org/images/cloud/bullseye/latest/$VM_PROVISION_BASEIMG
        ;;
    e)  # Debian 12
        VM_PROVISION_BASEIMG=debian-12-genericcloud-amd64.qcow2
        VM_PROVISION_BASEIMG_URL=https://cloud.debian.org/images/cloud/bookworm/latest/$VM_PROVISION_BASEIMG
        ;;
    f)  # Fedora 38
        VM_PROVISION_BASEIMG=Fedora-Cloud-Base-38-1.6.x86_64.qcow2
        VM_PROVISION_BASEIMG_URL=https://download.fedoraproject.org/pub/fedora/linux/releases/38/Cloud/x86_64/images/$VM_PROVISION_BASEIMG
        ;;
    g)  # openSUSE Leap 15.5
        VM_PROVISION_BASEIMG=openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2
        VM_PROVISION_BASEIMG_URL=https://download.opensuse.org/distribution/leap/15.5/appliances/$VM_PROVISION_BASEIMG
        ;;
    h)  # Rocky Linux 8
        VM_PROVISION_BASEIMG=Rocky-8-GenericCloud.latest.x86_64.qcow2
        VM_PROVISION_BASEIMG_URL=http://dl.rockylinux.org/pub/rocky/8/images/x86_64/$VM_PROVISION_BASEIMG
        ;;
    i)  # Rocky Linux 9
        VM_PROVISION_BASEIMG=Rocky-9-GenericCloud.latest.x86_64.qcow2
        VM_PROVISION_BASEIMG_URL=http://dl.rockylinux.org/stg/rocky/9/images/x86_64/$VM_PROVISION_BASEIMG
        ;;
    j)  # Ubuntu 20.04 LTS
        VM_PROVISION_BASEIMG=focal-server-cloudimg-amd64.img
        VM_PROVISION_BASEIMG_URL=https://cloud-images.ubuntu.com/focal/current/$VM_PROVISION_BASEIMG
        ;;
    k)  # Ubuntu 22.04 LTS
        VM_PROVISION_BASEIMG=jammy-server-cloudimg-amd64.img
        VM_PROVISION_BASEIMG_URL=https://cloud-images.ubuntu.com/jammy/current/$VM_PROVISION_BASEIMG
        ;;
    l)  # Ubuntu 23.04
        VM_PROVISION_BASEIMG=lunar-server-cloudimg-amd64.img
        VM_PROVISION_BASEIMG_URL=https://cloud-images.ubuntu.com/lunar/current/$VM_PROVISION_BASEIMG
        ;;
    *)
        # User canceled menu selection
        printerr "\n\nERROR: distro selection canceled.\n\n"
        fatalerror
        ;;
    esac
}

# downloadimage will check if images/$VM_PROVISION_BASEIMG exists, and if not,
# attempt to download it using $VM_PROVISION_BASEIMG_URL.
downloadimage() {
    # If necessary, download the selected base image.
    mkdir -p images
    if [ ! -f "images/$VM_PROVISION_BASEIMG" ]; then
        printf "\n\nDownloading %s...\n\n" "$VM_PROVISION_BASEIMG"
        curl -L -o "images/$VM_PROVISION_BASEIMG" "$VM_PROVISION_BASEIMG_URL"
        if [ $? -ne 0 ]; then
            printerr "\n\nERROR: couldn't download %s from %s\n" \
                "$VM_PROVISION_BASEIMG" "$VM_PROVISION_BASEIMG_URL"
            fatalerror
        fi
    fi
}

# After each run, we save the user's options to a preferences file. We will
# reload them as default values for this run. If not present, we will start
# with some reasonable default/example values.
getprefs() {
    # Look for a suitable SSH public key path
    if [ -f "${HOME}/.ssh/id_ed25519.pub" ]; then
        found_pubkey="${HOME}/.ssh/id_ed25519.pub"
    elif [ -f "${HOME}/.ssh/id_rsa.pub" ]; then
        found_pubkey="${HOME}/.ssh/id_rsa.pub"
    else
        found_pubkey=""
    fi

    # Set up defaults if there is no prefs file
    if [ ! -f .prefs ]; then
        opt_hostname=""
        opt_domain=""
        opt_ip=""
        opt_gw=""
        opt_dns=""
        opt_bridge=br0
        opt_user="$USER"
        opt_pubkey="$found_pubkey"
        opt_ram=4096
        opt_disk=16
        opt_cpus=1

        return
    fi

    # Prefs file is in the format:
    # hostname^^domain^^ip^^gw^^dns^^bridge^^user^^pubkey^^ram^^disk^^cpus^^
    # We will extract each value with awk. The awk FS is a regular expression,
    # so ^ needs to be escaped
    opt_hostname="$(awk -F "\\\\^\\\\^" 'NR==1 {print $1}' < .prefs)"
    opt_domain="$(awk -F "\\\\^\\\\^" 'NR==1 {print $2}' < .prefs)"
    opt_ip="$(awk -F "\\\\^\\\\^" 'NR==1 {print $3}' < .prefs)"
    opt_gw="$(awk -F "\\\\^\\\\^" 'NR==1 {print $4}' < .prefs)"
    opt_dns="$(awk -F "\\\\^\\\\^" 'NR==1 {print $5}' < .prefs)"
    opt_bridge="$(awk -F "\\\\^\\\\^" 'NR==1 {print $6}' < .prefs)"
    opt_user="$(awk -F "\\\\^\\\\^" 'NR==1 {print $7}' < .prefs)"
    opt_pubkey="$(awk -F "\\\\^\\\\^" 'NR==1 {print $8}' < .prefs)"
    opt_ram="$(awk -F "\\\\^\\\\^" 'NR==1 {print $9}' < .prefs)"
    opt_disk="$(awk -F "\\\\^\\\\^" 'NR==1 {print $10}' < .prefs)"
    opt_cpus="$(awk -F "\\\\^\\\\^" 'NR==1 {print $11}' < .prefs)"

    # If a preference is missing for some reason, set default value as above
    [ -z "$opt_hostname" ] && opt_hostname=""
    [ -z "$opt_domain" ] && opt_domain=""
    [ -z "$opt_ip" ] && opt_ip=""
    [ -z "$opt_gw" ] && opt_gw=""
    [ -z "$opt_dns" ] && opt_dns=""
    [ -z "$opt_bridge" ] && opt_bridge=br0
    [ -z "$opt_user" ] && opt_user="$USER"
    [ -z "$opt_pubkey" ] && opt_pubkey="$found_pubkey"
    [ -z "$opt_ram" ] && opt_ram=4096
    [ -z "$opt_disk" ] && opt_disk=16
    [ -z "$opt_cpus" ] && cpus=1
}

# overridedefaults replaces the default/preferences values with any
# environment variables provided by the user.
overridedefaults() {
    [ -n "$VM_PROVISION_HOSTNAME" ] && opt_hostname="$VM_PROVISION_HOSTNAME"
    [ -n "$VM_PROVISION_DOMAIN" ] && opt_domain="$VM_PROVISION_DOMAIN"
    [ -n "$VM_PROVISION_IP" ] && opt_ip="$VM_PROVISION_IP"
    [ -n "$VM_PROVISION_GW" ] && opt_ip="$VM_PROVISION_GW"
    [ -n "$VM_PROVISION_DNS" ] && opt_dns="$VM_PROVISION_DNS"
    [ -n "$VM_PROVISION_BRIDGE" ] && opt_bridge="$VM_PROVISION_BRIDGE"
    [ -n "$VM_PROVISION_USER" ] && opt_user="$VM_PROVISION_USER"
    [ -n "$VM_PROVISION_PUBKEY" ] && opt_pubkey="$VM_PROVISION_PUBKEY"
    [ -n "$VM_PROVISION_RAM" ] && opt_ram="$VM_PROVISION_RAM"
    [ -n "$VM_PROVISION_DISK" ] && opt_disk="$VM_PROVISION_DISK"
    [ -n "$VM_PROVISION_CPUS" ] && opt_disk="$VM_PROVISION_CPUS"
}

optionsform() {
    # If *all* options are present as environment variables, we don't display
    # the form. We will simulate the output of dialog.
    if [ -n "$VM_PROVISION_HOSTNAME" -a -n "$VM_PROVISION_DOMAIN" \
            -a -n "$VM_PROVISION_IP" -a -n "$VM_PROVISION_GW" \
            -a -n "$VM_PROVISION_DNS" -a -n "$VM_PROVISION_BRIDGE" \
            -a -n "$VM_PROVISION_USER" -a -n "$VM_PROVISION_PUBKEY" \
            -a -n "$VM_PROVISION_RAM" -a -n "$VM_PROVISION_DISK" \
            -a -n "$VM_PROVISION_CPUS" ]; then

        printf "%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^" \
            "$VM_PROVISION_HOSTNAME" "$VM_PROVISION_DOMAIN" \
            "$VM_PROVISION_IP" "$VM_PROVISION_GW" "$VM_PROVISION_DNS" \
            "$VM_PROVISION_BRIDGE" "$VM_PROVISION_USER" \
            "$VM_PROVISION_PUBKEY" "$VM_PROVISION_RAM" \
            "$VM_PROVISION_DISK" "$VM_PROVISION_CPUS" > $tmpfile

        # Clear all of the environment-provided values so if there's a
        # validation error, and we re-prompt, we don't just create an infinite
        # loop of not showing the form.
        unset VM_PROVISION_HOSTNAME
        unset VM_PROVISION_DOMAIN
        unset VM_PROVISION_IP
        unset VM_PROVISION_GW
        unset VM_PROVISION_DNS
        unset VM_PROVISION_BRIDGE
        unset VM_PROVISION_USER
        unset VM_PROVISION_PUBKEY
        unset VM_PROVISION_RAM
        unset VM_PROVISION_DISK
        unset VM_PROVISION_CPUS

        return
    fi

    dialog --title "VM Options" \
        --output-separator "^^" \
        --form "Please provide the following parameters for the new VM:\n(Up/Down arrows to move between fields)" \
        20 75 12 \
        "        Hostname:" 1  2 "$opt_hostname" 1  20 32 100 \
        "     Domain name:" 2  2 "$opt_domain"   2  20 32 100 \
        " IP address/CIDR:" 3  2 "$opt_ip"       3  20 19  18 \
        "      Gateway IP:" 4  2 "$opt_gw"       4  20 19  18 \
        "   DNS Server(s):" 5  2 "$opt_dns"      5  20 50  50 \
        "Bridge interface:" 6  2 "$opt_bridge"   6  20 10  20 \
        "        Username:" 7  2 "$opt_user"     7  20 32  32 \
        " SSH pubkey path:" 8  2 "$opt_pubkey"   8  20 50 255 \
        "   RAM size (MB):" 9  2 "$opt_ram"      9  20  6  10 \
        "  Disk size (GB):" 10 2 "$opt_disk"     10 20  4  10 \
        "       # of CPUs:" 11 2 "$opt_cpus"     11 20  4  10 \
        2>$tmpfile
    clear

    if [ -z "$(cat $tmpfile)" ]; then
        # User canceled form
        printerr "\n\nERROR: options form canceled.\n\n"
        fatalerror
    fi
}

# loadoptions reads the output file from the form and changes the $opt_*
# values to the user-provided values.
#
# This is basically doing the same thing as when we load from the preferences
# file, so we should probably factor out the common code here. Something for
# the future...
loadoptions() {
    # dialog  --output-separator "^^" --form output file is in the format:
    # hostname^^domain^^ip^^dns^^bridge^^user^^pubkey^^ram^^disk^^cpus^^
    # We will extract each value with awk. The awk FS is a regular expression,
    # so ^ needs to be escaped
    opt_hostname="$(awk -F "\\\\^\\\\^" 'NR==1 {print $1}' < "$tmpfile")"
    opt_domain="$(awk -F "\\\\^\\\\^" 'NR==1 {print $2}' < "$tmpfile")"
    opt_ip="$(awk -F "\\\\^\\\\^" 'NR==1 {print $3}' < "$tmpfile")"
    opt_gw="$(awk -F "\\\\^\\\\^" 'NR==1 {print $4}' < "$tmpfile")"
    opt_dns="$(awk -F "\\\\^\\\\^" 'NR==1 {print $5}' < "$tmpfile")"
    opt_bridge="$(awk -F "\\\\^\\\\^" 'NR==1 {print $6}' < "$tmpfile")"
    opt_user="$(awk -F "\\\\^\\\\^" 'NR==1 {print $7}' < "$tmpfile")"
    opt_pubkey="$(awk -F "\\\\^\\\\^" 'NR==1 {print $8}' < "$tmpfile")"
    opt_ram="$(awk -F "\\\\^\\\\^" 'NR==1 {print $9}' < "$tmpfile")"
    opt_disk="$(awk -F "\\\\^\\\\^" 'NR==1 {print $10}' < "$tmpfile")"
    opt_cpus="$(awk -F "\\\\^\\\\^" 'NR==1 {print $11}' < "$tmpfile")"
}

# validateinput will attempt to do some sanity checks on the provided values.
# First we'll trim leading and trailing whitespace with sed, then use grep to
# apply some regular expressions. If we encounter a missing or invalid value,
# we'll alert the user and bail out (validateinput will be called in a loop
# that will display the form again. If all values look good, we set valid=YES
# so our caller can abandon the form input loop.
validateinput() {
    # assume we'll find an error
    valid=NO

    # strip leading/trailing space
    sed_pgm1='s/^[[:space:]]*//'
    sed_pgm2='s/[[:space:]]*$//'
    opt_hostname="$(echo "$opt_hostname" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_domain="$(echo "$opt_domain" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_ip="$(echo "$opt_ip" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_gw="$(echo "$opt_gw" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_dns="$(echo "$opt_dns" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_bridge="$(echo "$opt_bridge" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_user="$(echo "$opt_user" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_pubkey="$(echo "$opt_pubkey" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_ram="$(echo "$opt_ram" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_disk="$(echo "$opt_disk" | sed -e "$sed_pgm1" -e "$sed_pgm2")"
    opt_cpus="$(echo "$opt_cpus" | sed -e "$sed_pgm1" -e "$sed_pgm2")"

    # All values are required. Let's check for that first.
    required=OK
    [ -z "$opt_hostname" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The hostname field is required." 7 50
    [ -z "$opt_domain" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The domain name field is required." 7 50
    [ -z "$opt_ip" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The IP address field is required." 7 50
    [ -z "$opt_gw" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The gateway address field is required." 7 50
    [ -z "$opt_dns" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The DNS servers field is required." 7 50
    [ -z "$opt_bridge" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The bridge interface field is required." 7 50
    [ -z "$opt_user" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The username field is required." 7 50
    [ -z "$opt_pubkey" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The SSH public key path is required." 7 50
    [ -z "$opt_ram" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The RAM size field is required." 7 50
    [ -z "$opt_disk" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The disk size field is required." 7 50
    [ -z "$opt_cpus" ] && required=BAD && \
        dialog --title "Validation Error" \
            --msgbox "The number of CPUs is required." 7 50
    [ $required == BAD ] && return

    # Now that we have confirmed all values are present, we'll check each one.

    if ! echo -n "$opt_hostname" | grep -E -q '^[A-Za-z0-9][A-Za-z0-9\-]*$'; then
        dialog --title "Validation Error" \
            --msgbox "Hostname must consist only of letters, numbers, and the hyphen (-). A hostname may not start with a hyphen." \
            7 50
        return
    fi

    # Don't create a VM with the same name as an existing one.
    if [ -e "vms/$opt_hostname" ]; then
        dialog --title "Validation Error" \
            --msgbox "The VM $opt_hostname already exists in the vms directory." \
            7 50
        return
    fi

    if ! echo -n "$opt_domain" | grep -E -q '^[A-Za-z0-9][A-Za-z0-9.-]*$'; then
        dialog --title "Validation Error" \
            --msgbox "Domain name must consist only of letters, numbers, hyphens, and periods." \
            7 50
        return
    fi

    if ! echo -n "$opt_ip" | grep -E -q '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$'; then
        dialog --title "Validation Error" \
            --msgbox "IP address must be an IPv4 address of the form '1.2.3.4' or '1.2.3.4/24'." \
            7 50
        return
    fi

    if ! echo -n "$opt_gw" | grep -E -q '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        dialog --title "Validation Error" \
            --msgbox "Gateway address must be an IPv4 address of the form '1.2.3.4'." \
            7 50
        return
    fi

    if ! echo -n "$opt_dns" | grep -E -q '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}( [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})?$'; then
        dialog --title "Validation Error" \
            --msgbox "DNS servers must be a space-delimited list of IPv4 addresses" \
            7 50
        return
    fi

    # We'll assume bridge interface is correct, I'm not sure of the
    # requirements the kernel imposes on interface names.

    if ! echo -n "$opt_user" | grep -E -q '^[a-zA-Z][a-zA-Z0-9-]*$'; then
        dialog --title "Validation Error" \
            --msgbox "Usernames may only contain letters, numbers, and the hyphen. Usernames may not start with a hypen or a number." \
            7 50
        return
    fi

    if [ ! -f "$opt_pubkey" ]; then
        dialog --title "Validation Error" \
            --msgbox "The public key file does not exist." \
            7 50
        return
    fi

    # We can do a couple quick sanity checks of the public key file
    # First we can check for the "-----BEGIN OPENSSH PRIVATE KEY-----" header;
    # it's enough just to look for the first "-" since public keys in the right
    # format don't have that.
    if grep -E -q '^-' "$opt_pubkey"; then
        dialog --title "Validation Error" \
            --msgbox "The public key file appears to be a private key, not a public key." \
            7 50
        return
    fi

    # If it's a real key, ssk-keygen should be able to calculate a fingerprint
    # for it.
    if ! ssh-keygen -l -f "$opt_pubkey" > /dev/null 2>&1; then
        dialog --title "Validation Error" \
            --msgbox "The public key file does not appear to be valid." \
            7 50
        return
    fi

    if ! [ "$opt_ram" -ge 256 ]; then
        dialog --title "Validation Error" \
            --msgbox "RAM size (MB) must be a number 256 or larger." \
            7 50
        return
    fi

    if ! [ "$opt_disk" -ge 1 ]; then
        dialog --title "Validation Error" \
            --msgbox "Disk size (GB) must be a number 1 or larger." \
            7 50
        return
    fi

    if ! [ "$opt_cpus" -ge 1 ]; then
        dialog --title "Validation Error" \
            --msgbox "Number of CPUs must be 1 or larger." \
            7 50
        return
    fi

    # If we made it this far, everything checks out.
    valid=YES
}

# makednslist will take the space-separated opt_dns and turn it into
# a comma-separated list in the format for cloud-init and place it in
# opt_dns_comma
makednslist() {
    opt_dns_comma=$(echo -n "$opt_dns" | sed 's/ /, /g')
}

# provision builds the VM based on all of the opt_* variables.
provision() {
    mkdir -p "vms/$opt_hostname"
    if [ $? -ne 0 ]; then
        printerr "\nSomething went wrong creating vms/%s\n" "$opt_hostname"
        printerr "Aborting.\n"
        fatalerror
    fi

    printf "\nCopying images/%s to vms/%s/hd-%s.img...\n" \
        "$VM_PROVISION_BASEIMG" "$opt_hostname" "$opt_hostname"
    cp "images/$VM_PROVISION_BASEIMG" \
        "vms/${opt_hostname}/hd-${opt_hostname}.img"
    if [ $? -ne 0 ]; then
        printerr "\nSomething went wrong copying the base image.\n"
        printerr "Aborting.\n"
        fatalerror
    fi

    printf "Expanding disk image to %dG\n" $opt_disk
    qemu-img resize -f qcow2 "vms/${opt_hostname}/hd-${opt_hostname}.img" \
        ${opt_disk}G

    # Generate a UUID for the machine
    if [ -e /proc/sys/kernel/random/uuid ]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    else
        uuid=$(uuidgen)
    fi

    # Generate a valid unicast MAC address
    # https://stackoverflow.com/a/42661696/4472549
    macaddress=$(hexdump -n 6 -ve '1/1 "%.2x "' /dev/random | awk -v a="2,6,a,e" -v r="$RANDOM" 'BEGIN{srand(r);}NR==1{split(a,b,",");r=int(rand()*4+1);printf "%s%s:%s:%s:%s:%s:%s\n",substr($1,0,1),b[r],$2,$3,$4,$5,$6}')

    # Create the cloud-init.user.cfg file
    cat > "vms/$opt_hostname/cloud-init.user.cfg" << __EOF__
#cloud-config
hostname: $opt_hostname
fqdn: $opt_hostname.$opt_domain
manage_etc_hosts: true
users:
  - name: $opt_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    homedir: /home/$opt_user
    shell: /bin/bash
    lock_passwd: true
    ssh-authorized-keys:
      - $(head -n 1 "$opt_pubkey")
ssh_pwauth: false
__EOF__

    # Create the cloud-init.net.cfg file
    cat > "vms/$opt_hostname/cloud-init.net.cfg" << __EOF__
version: 2
ethernets:
  id0:
    match:
      macaddress: "$macaddress"
    set-name: "eth0"
    dhcp4: false
    addresses:
      - $opt_ip
    gateway4: $opt_gw
    nameservers:
      search: [$opt_domain]
      addresses: [$opt_dns_comma]
__EOF__

    # Create the cloud-init.meta.cfg file
    printf "instance-id: %s\n" > "vms/$opt_hostname/cloud-init.meta.cfg"

    # Create the cloud-init data disk image
    printf "Creating cloud-init disk at vms/%s/meta-%s.img...\n" \
        $opt_hostname $opt_hostname
    cloud-localds -v --network-config=vms/$opt_hostname/cloud-init.net.cfg \
        vms/$opt_hostname/meta-$opt_hostname.img \
        vms/$opt_hostname/cloud-init.user.cfg \
        vms/$opt_hostname/cloud-init.meta.cfg
    if [ $? -ne 0 ]; then
        printerr "\nSomething went wrong creating the cloud-init disk.\n"
        printerr "Aborting.\n"
        fatalerror
    fi

    # We want to get the IP without the netmask, if present
    connect_ip=$(echo $opt_ip | sed -E 's^([0-9.]+)(/.+)?$^\1^')

    # Write the startup script
    cat > "vms/$opt_hostname/start-$opt_hostname.sh" << __EOF__
#!/bin/sh

# Check for presence of hard disk file as a sanity check
if [ ! -f hd-$opt_hostname.img ]; then
    echo "ERROR: this start script must be run from the directory where" 1>&2
    echo "       the VM's files (e.g. hard disk image) are. Please cd" 1>&2
    echo "       to that directory and try again." 1>&2
    exit 1
fi

qemu-system-x86_64 \\
    -name $opt_hostname \\
    -uuid $uuid \\
    -drive file=hd-$opt_hostname.img,format=qcow2,if=virtio \\
    -drive file=meta-$opt_hostname.img,format=raw,if=virtio \\
    -m ${opt_ram}M -smp ${opt_cpus} -enable-kvm -cpu host \\
    -net nic,model=virtio,macaddr=$macaddress -net bridge,br=$opt_bridge \\
    -display none -daemonize \\
    -chardev socket,id=char0,path=${opt_hostname}-serial,server=on,wait=off \\
    -serial chardev:char0 \\
    -chardev socket,id=char1,path=${opt_hostname}-mon,server=on,wait=off \\
    -monitor chardev:char1 \\
    -smbios type=1,serial=$uuid \\
    -smbios type=2,serial=$uuid \\
    -smbios type=1,uuid=$uuid

printf "VM starting. SSH to it at %s.\n" "$connect_ip"
__EOF__

    chmod +x "vms/$opt_hostname/start-$opt_hostname.sh"
}

# printinstructions displayed the starting and login instructions for the new
# VM.
printinstructions() {
    # We want to get the IP without the netmask, if present
    connect_ip=$(echo $opt_ip | sed -E 's^([0-9.]+)(/.+)?$^\1^')

    printf "\n\n----------------------------------------------\n"
    printf "Your new VM is ready to go!\n\n"
    printf "cd vms/%s\n" "$opt_hostname"
    printf "Then start it with ./start-%s.sh\n\n" "$opt_hostname"
    printf "After the VM boots, you can connect with:\n"
    printf "  ssh %s@%s\n\n" "$opt_user" "$connect_ip"
    printf "(If necessary, point to your SSH private key with -i)\n\n"
    printf -- "----------------------------------------------\n"
}

# saveprefs writes the final values to .prefs. We don't just copy tmpfile over
# because we may have changed the values when stripping leading and trailing
# spaces.
saveprefs() {
    printf "%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^%s^^" \
        "$opt_hostname" "$opt_domain" "$opt_ip" "$opt_gw" "$opt_dns" \
        "$opt_bridge" "$opt_user" "$opt_pubkey" "$opt_ram" \
        "$opt_disk" "$opt_cpus" > .prefs
}

checkhw
checkprereqs
selectdistro
downloadimage
getprefs
overridedefaults

# Loop until we have valid options
valid=NO
while [ $valid == NO ]; do
    optionsform
    loadoptions
    validateinput
done

makednslist
provision
printinstructions

# After a successful run, save the answers as the starting point for next time
# and clean up the tmpfile.
saveprefs
rm -f $tmpfile
