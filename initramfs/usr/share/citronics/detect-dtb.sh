#!/bin/sh
# Board-variant detection for the Fairphone 2 family.
#
# Why this exists: the FP2 mainboard is used both in a phone and on a carrier
# board ("the rig") with no battery and no panel, and the two need different
# device trees:
#
#   qcom-msm8974pro-fairphone-fp2.dtb       phone: panel enabled, vendor 4.45 V
#                                           input floor, XPU err-fatal armed
#   qcom-msm8974pro-fairphone-fp2-rig.dtb   carrier: MDSS disabled (no panel),
#                                           4.30 V input floor (with no cell,
#                                           the 4.45 V floor folds back the
#                                           board's only supply on load onsets),
#                                           XPU err-fatal disarmed
#
# Until now the choice lived in $deviceinfo_dtb, i.e. in a human's memory. Both
# directions of forgetting have a cost: a rig booted with the phone DTB resets
# under load, and a phone booted with the rig DTB has no display. Detect it
# instead, and let an explicit setting still win.
#
# Testable: override PS_ROOT (power-supply sysfs) and DT_ROOT (device tree) to
# exercise both branches without the hardware.

PS_ROOT="${PS_ROOT:-/sys/class/power_supply}"
DT_ROOT="${DT_ROOT:-/proc/device-tree}"

FP2_PHONE_DTB="qcom-msm8974pro-fairphone-fp2.dtb"
FP2_RIG_DTB="qcom-msm8974pro-fairphone-fp2-rig.dtb"

# citronics_battery_state -> "present" | "absent" | "unknown"
citronics_battery_state() {
	_seen=0
	for _p in "$PS_ROOT"/*; do
		[ -r "$_p/type" ] || continue
		[ "$(cat "$_p/type" 2>/dev/null)" = "Battery" ] || continue
		_seen=1
		# A pack that is present reports 1. Absent reports 0. Missing the
		# attribute at all is treated as present: never disable a display on
		# the strength of an attribute the driver did not implement.
		if [ "$(cat "$_p/present" 2>/dev/null || echo 1)" = "1" ]; then
			echo present
			return 0
		fi
	done
	[ "$_seen" = 1 ] && echo absent || echo unknown
}

# citronics_detect_dtb <kver> -> prints the DTB filename to use
#
# Order of authority:
#   1. $deviceinfo_dtb set to anything other than "auto"  -> obeyed verbatim
#   2. a battery node reporting absent, and the rig DTB exists in the kernel
#      package                                            -> rig
#   3. anything else                                      -> phone
#
# Rationale for the default: the phone DTB drives a display and uses the vendor
# input floor, so an incorrect guess is a fixture that runs conservatively, not
# a user's phone with a black screen.
citronics_detect_dtb() {
	_kver="$1"
	_dtbdir="/usr/lib/linux-image-$_kver"

	case "${deviceinfo_dtb:-}" in
		"" | auto | AUTO) ;;
		*)
			echo "$deviceinfo_dtb"
			return 0
			;;
	esac

	_bat="$(citronics_battery_state)"
	_have_rig=no
	if [ -f "$_dtbdir/$FP2_RIG_DTB" ] || [ -f "$_dtbdir/qcom/$FP2_RIG_DTB" ]; then
		_have_rig=yes
	fi

	# The reason is logged here, by the code that actually decided. An earlier
	# version left the explanation to a second function that re-read
	# $deviceinfo_dtb — which the caller had already overwritten with the
	# resolved name, so every auto-detected boot claimed to have been set
	# explicitly. Keep the decision and its explanation together.
	if [ "$_bat" = "absent" ] && [ "$_have_rig" = "yes" ]; then
		echo "DTB auto-detected: $FP2_RIG_DTB (no battery present => carrier rig; override with deviceinfo_dtb in /etc/deviceinfo)" >&2
		echo "$FP2_RIG_DTB"
	else
		case "$_bat" in
		present) _why="battery present => phone" ;;
		absent)  _why="no battery, but this kernel package ships no rig DTB" ;;
		*)       _why="no battery node to read; assuming phone" ;;
		esac
		echo "DTB auto-detected: $FP2_PHONE_DTB ($_why; override with deviceinfo_dtb in /etc/deviceinfo)" >&2
		echo "$FP2_PHONE_DTB"
	fi
}

# citronics_set_extlinux_fdt <dtb> [conf]
#
# Copying the right DTB into /boot is only half the job: lk2nd loads whatever
# extlinux.conf's "fdt" line names, so a correct copy with a stale fdt line
# still boots the wrong tree. Rewrite only lines that already point at a known
# FP2 DTB, so unrelated entries in a multi-label config are left alone.
citronics_set_extlinux_fdt() {
	_dtb="$1"
	_conf="${2:-/boot/extlinux/extlinux.conf}"
	[ -f "$_conf" ] || return 0

	if ! grep -qE "^[[:space:]]*fdt[[:space:]]+.*(${FP2_PHONE_DTB}|${FP2_RIG_DTB})" "$_conf"; then
		echo "extlinux.conf has no FP2 fdt line to update, leaving it alone" >&2
		return 0
	fi
	if grep -qE "^[[:space:]]*fdt[[:space:]]+/?${_dtb}\$" "$_conf"; then
		return 0			# already correct, stay idempotent
	fi

	sed -i -E "s@^([[:space:]]*)fdt[[:space:]]+.*(${FP2_PHONE_DTB}|${FP2_RIG_DTB})[[:space:]]*\$@\1fdt /${_dtb}@" "$_conf"
	echo "extlinux.conf fdt -> /$_dtb" >&2
}
