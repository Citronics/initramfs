#!/bin/sh
# This file will be in /init_functions.sh inside the initramfs.

# clobbering variables by not setting them if they have
# a value already!
CONFIGFS="/config/usb_gadget"
CONFIGFS_ACM_FUNCTION="acm.usb0"
HOST_IP="${unudhcpd_host_ip:-10.0.42.1}"

deviceinfo_getty="${deviceinfo_getty:-}"
deviceinfo_name="${deviceinfo_name:-}"
deviceinfo_codename="${deviceinfo_codename:-}"

get_kernel_param() {
    local param="$1"
    for word in $(cat /proc/cmdline); do
        case "$word" in
            $param=*) echo "${word#*=}"; return ;;
        esac
    done
}

echo_kmsg() {
    echo "$LOG_PREFIX $*" > /dev/kmsg
}

mount_proc_sys_dev() {
    mount -t proc -o nodev,noexec,nosuid proc /proc || echo_kmsg "Couldn't mount /proc"
    mount -t sysfs -o nodev,noexec,nosuid sysfs /sys || echo_kmsg "Couldn't mount /sys"
    mount -t devtmpfs -o mode=0755,nosuid dev /dev || echo_kmsg "Couldn't mount /dev"
    mount -t tmpfs -o nosuid,nodev,mode=0755 run /run || echo_kmsg "Couldn't mount /run"

    mkdir /config
    mount -t configfs -o nodev,noexec,nosuid configfs /config || echo_kmsg "Couldn't mount /config"

    mkdir -p /dev/pts
    mount -t devpts devpts /dev/pts || echo_kmsg "Couldn't mount /dev/pts"

    ln -s /proc/self/fd /dev/fd
}

setup_firmware_path() {
    # Add the citronics-specific path to the firmware search paths.
    # This should be sufficient on kernel 3.10+, before that we need
    # the kernel calling udev (and in our case /usr/lib/firmwareload.sh)
    # to load the firmware for the kernel.
    SYS=/sys/module/firmware_class/parameters/path
    if ! [ -e "$SYS" ]; then
        echo_kmsg "Kernel does not support setting the firmware image search path. Skipping."
        return
    fi
    # shellcheck disable=SC3037
    echo -n /lib/firmware/ >$SYS
}

setup_mdev() {
    # Start mdev daemon
    mdev -d
}

load_modules() {
	local file="$1"
	local modules="$2"
	[ -f "$file" ] && modules="$modules $(grep -v ^\# "$file")"
	modprobe -a $modules
}

fail_halt_boot() {
    debug_shell
    echo_kmsg "Looping forever"
    while true; do
        sleep 1
    done
}

debug_shell() {
    echo_kmsg "Entering debug shell"

    # mount pstore, if possible
    if [ -d /sys/fs/pstore ]; then
        mount -t pstore pstore /sys/fs/pstore || true
    fi

    mount -t debugfs none /sys/kernel/debug || true
    # make a symlink like Android recoveries do
    ln -s /sys/kernel/debug /d

    setup_usb_network
    start_unudhcpd

	cat <<-EOF > /README
	citronics debug shell

	  Device: $deviceinfo_name ($deviceinfo_codename)
	  Kernel: $(uname -r)
	  OS ver: $VERSION
	  initrd: $INITRAMFS_PKG_VERSION
	EOF

	# Display some info
	cat <<-EOF > /etc/profile
	cat /README
	. /functions.sh
	EOF

	cat <<-EOF > /sbin/citronics_getty
	#!/bin/sh
	/bin/sh -l
	EOF
	chmod +x /sbin/citronics_getty

    # Get the console (ttyX) associated with /dev/console
    local active_console
    active_console="$(cat /sys/devices/virtual/tty/tty0/active)"
    # Get a list of all active TTYs include serial ports
    local serial_ports
    serial_ports="$(cat /sys/devices/virtual/tty/console/active)"
    # Get the getty device too (might not be active)
    local getty
    getty="$(echo "$deviceinfo_getty" | cut -d';' -f1)"

    # Run getty's on the consoles
    for tty in $serial_ports; do
        # Some ports we handle explicitly below to make sure we don't
        # accidentally spawn two getty's on them
        if echo "tty0 tty1 $getty" | grep -q "$tty" ; then
            continue
        fi
        run_getty "$tty"
    done

    if [ -n "$getty" ]; then
        run_getty "$getty"
    fi

    # Rewrite tty to tty1 if tty0 is active
    if [ "$active_console" = "tty0" ]; then
        active_console="tty1"
    fi

    # Prevent sysrq help messages from being printed to serial
    echo 0 > /proc/sys/kernel/sysrq

    # Getty on the display
    run_getty "$active_console"

    telnetd -b "${HOST_IP}:23" -l /sbin/citronics_getty &
}

setup_usb_network() {
	# Only run once
	_marker="/tmp/_setup_usb_network"
	[ -e "$_marker" ] && return
	touch "$_marker"
	echo_kmsg "Setup usb network"
	modprobe libcomposite
	setup_usb_network_configfs
}

setup_usb_network_configfs() {
	# See: https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt
	local skip_udc="$1"

	if ! [ -e "$CONFIGFS" ]; then
		echo_kmsg "$CONFIGFS does not exist, skipping configfs usb gadget"
		return
	fi

	if [ -z "$(get_usb_udc)" ]; then
		echo_kmsg "  No UDC found, skipping usb gadget"
		return
	fi

	# Default values for USB-related deviceinfo variables
	usb_idVendor="${deviceinfo_usb_idVendor:-0x1d6b}"   # default: Linux Foundation.
	usb_idProduct="${deviceinfo_usb_idProduct:-0x0042}"
	usb_serialnumber="${deviceinfo_usb_serialnumber:-citronics}"
	usb_network_function="${deviceinfo_usb_network_function:-ncm.usb0}"
	usb_network_function_fallback="rndis.usb0"

	echo_kmsg "  Setting up USB gadget through configfs"
	# Create an usb gadet configuration
	mkdir $CONFIGFS/g1 || echo_kmsg "  Couldn't create $CONFIGFS/g1"
	echo "$usb_idVendor"  > "$CONFIGFS/g1/idVendor"
	echo "$usb_idProduct" > "$CONFIGFS/g1/idProduct"

	# Create english (0x409) strings
	mkdir $CONFIGFS/g1/strings/0x409 || echo_kmsg "  Couldn't create $CONFIGFS/g1/strings/0x409"

	# shellcheck disable=SC2154
	echo "$deviceinfo_manufacturer" > "$CONFIGFS/g1/strings/0x409/manufacturer"
	echo "$usb_serialnumber"        > "$CONFIGFS/g1/strings/0x409/serialnumber"
	# shellcheck disable=SC2154
	echo "$deviceinfo_name"         > "$CONFIGFS/g1/strings/0x409/product"

	# Create network function.
	if ! mkdir $CONFIGFS/g1/functions/"$usb_network_function"; then
		# Try the fallback function next
		if mkdir $CONFIGFS/g1/functions/"$usb_network_function_fallback"; then
			usb_network_function="$usb_network_function_fallback"
		fi
	fi

	# Create configuration instance for the gadget
	mkdir $CONFIGFS/g1/configs/c.1 \
		|| echo_kmsg "  Couldn't create $CONFIGFS/g1/configs/c.1"
	mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 \
		|| echo_kmsg "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
	echo "USB network" > $CONFIGFS/g1/configs/c.1/strings/0x409/configuration \
		|| echo_kmsg "  Couldn't write configration name"

	# Link the network instance to the configuration
	ln -s $CONFIGFS/g1/functions/"$usb_network_function" $CONFIGFS/g1/configs/c.1 \
		|| echo_kmsg "  Couldn't symlink $usb_network_function"
}

start_unudhcpd() {
	# Only run once
	[ "$(pidof unudhcpd)" ] && return

	# Skip if disabled
	# shellcheck disable=SC2154
	if [ "$deviceinfo_disable_dhcpd" = "true" ]; then
		return
	fi

	local client_ip="${unudhcpd_client_ip:-10.0.42.2}"
	echo_kmsg "Starting unudhcpd with server ip $HOST_IP, client ip: $client_ip"

	# Get usb interface
	usb_network_function="${deviceinfo_usb_network_function:-ncm.usb0}"
	usb_network_function_fallback="rndis.usb0"
	if [ -n "$(cat $CONFIGFS/g1/UDC)" ]; then
		INTERFACE="$(
			cat "$CONFIGFS/g1/functions/$usb_network_function/ifname" 2>/dev/null ||
			cat "$CONFIGFS/g1/functions/$usb_network_function_fallback/ifname" 2>/dev/null ||
			echo ''
		)"
	else
		INTERFACE=""
	fi
	if [ -n "$INTERFACE" ]; then
		ifconfig "$INTERFACE" "$HOST_IP"
	elif ifconfig rndis0 "$HOST_IP" 2>/dev/null; then
		INTERFACE=rndis0
	elif ifconfig usb0 "$HOST_IP" 2>/dev/null; then
		INTERFACE=usb0
	elif ifconfig eth0 "$HOST_IP" 2>/dev/null; then
		INTERFACE=eth0
	fi

	if [ -z "$INTERFACE" ]; then
		echo_kmsg "  Could not find an interface to run a dhcp server on"
		echo_kmsg "  Interfaces:"
		ip link
		return
	fi

	echo_kmsg "  Using interface $INTERFACE"
	echo_kmsg "  Starting the DHCP daemon"
	(
		unudhcpd -i "$INTERFACE" -s "$HOST_IP" -c "$client_ip"
	) &
}

setup_usb_configfs_udc() {
    # Check if there's an USB Device Controller
    local _udc_dev
    _udc_dev="$(get_usb_udc)"

    # Remove any existing UDC to avoid "write error: Resource busy" when setting UDC again
    if [ "$(wc -w <$CONFIGFS/g1/UDC)" -gt 0 ]; then
        echo "" > "$CONFIGFS"/g1/UDC || echo "  Couldn't write to clear UDC"
    fi
    # Link the gadget instance to an USB Device Controller. This activates the gadget.
    echo "$_udc_dev" > "$CONFIGFS"/g1/UDC || echo_kmsg "  Couldn't write new UDC"
}

get_usb_udc() {
    local _udc_dev="${deviceinfo_usb_network_udc:-}"
    if [ -z "$_udc_dev" ]; then
        # shellcheck disable=SC2012
        _udc_dev=$(ls /sys/class/udc | head -1)
    fi

    echo "$_udc_dev"
}

run_getty() {
    {
        while /bin/getty -n -l /sbin/citronics_getty "$1" 115200 vt100; do
            sleep 0.2
        done
    } &
}

restore_consoles() {
    # Restore stdout and stderr to their original values if they
    # were stashed
    if [ -e "/proc/1/fd/3" ]; then
        exec 1>&3 2>&4
    elif ! grep -q "citronics.debug-shell" /proc/cmdline; then
        echo_kmsg "Disabling console output again (use 'citronics.debug-shell' to keep it enabled)"
        exec >/dev/null 2>&1
    fi

    echo ratelimit > /proc/sys/kernel/printk_devkmsg
}

get_partition_number() {
    local rootdev="$1"
    echo "$rootdev" | grep -oE 'p[0-9]+$' | sed 's/^p//'
}

has_unallocated_space() {
    parted -s "$1" print free | tail -n2 | \
            head -n1 | grep -qi "free space"
}

map_and_resize_root_partition() {
    local rootfs part_num rootfs_path base_device mapper_path output
    local timeout=10
    local delay=1

    rootfs=$(get_kernel_param "rootfs")
    rootfs=${rootfs#/dev/}
    rootfs_path="/dev/$rootfs"

    part_num=$(get_partition_number "$rootfs_path")
    base_device=$(echo "$rootfs_path" | sed -E "s/p${part_num}$//")
    mapper_path="/dev/mapper/${base_device##/dev/}p${part_num}"

    echo_kmsg "Waiting for rootfs device: $base_device"

    # Wait up to 10 seconds for the rootfs device to appear
    for i in $(seq 1 $timeout); do
        if [ -b "$base_device" ]; then
            echo_kmsg "Found rootfs device: $base_device"
            break
        fi
        sleep $delay
    done

    if [ ! -b "$base_device" ]; then
        echo_kmsg "Timeout waiting for rootfs device: $base_device"
        return 1
    fi

    if has_unallocated_space "$base_device"; then
        echo_kmsg "Resizing root partition $mapper_path on device $base_device"
        kpartx -d "$base_device"
        parted -f -s "$base_device" resizepart 2 100%
        sleep 1
        kpartx -asf "$base_device"
        sleep 1
        resize2fs "$mapper_path"
    else
        echo_kmsg "No resizing needed for root partition $mapper_path"
        kpartx -asf "$base_device"  # Ensure partitions are still mapped
    fi

    # --- Create symlinks (ex: /dev/mmcblk0p20p2 -> /dev/mapper/mmcblk0p20p2) ---
    if echo "$rootfs" | grep -qE '^mmcblk[0-9]+p[0-9]+p[0-9]+$'; then
        echo_kmsg "Creating subpartition symlinks for $base_device"
        for dev in /dev/mapper/$(basename "$base_device")p*; do
            ln -sf "$dev" "/dev/$(basename "$dev")"
        done
    else
        echo_kmsg "No subpartition mapping required for $rootfs"
    fi
}

mount_rootfs() {
    local rootfs
    rootfs=$(get_kernel_param "rootfs")
    # Wait for the rootfs device to be available, with a timeout of 10 seconds
    local rootfs_device="$rootfs"
    local timeout=20
    while [ ! -e "$rootfs_device" ] && [ $timeout -gt 0 ]; do
        echo_kmsg "Waiting for $rootfs_device to be available..."
        sleep 1
        timeout=$((timeout - 1))
    done

    if [ -e "$rootfs_device" ]; then
        mount "$rootfs_device" /sysroot
    else
        echo_kmsg "Device $rootfs_device not available after 10 seconds, cannot mount rootfs."
    fi
}

mount_boot_partition() {
    local boot_partition
    boot_partition=$(get_kernel_param "bootpart")

    # Remove the /dev/ prefix if present
    boot_partition=${boot_partition#/dev/}

    # Wait for the boot partition to be available, with a timeout of 10 seconds
    local boot_partition_device="/dev/$boot_partition"
    local timeout=10
    while [ ! -e "$boot_partition_device" ] && [ $timeout -gt 0 ]; do
        echo_kmsg "Waiting for $boot_partition_device to be available..."
        sleep 1
        timeout=$((timeout - 1))
    done

    if [ -e "$boot_partition_device" ]; then
        mount "$boot_partition_device" /sysroot/boot
    else
        echo_kmsg "Device $boot_partition_device not available after 10 seconds, cannot mount boot partition."
    fi
}
