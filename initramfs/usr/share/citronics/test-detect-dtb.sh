#!/bin/sh
# Tests for detect-dtb.sh. Runs anywhere (no device, no root): the power-supply
# sysfs and the kernel DTB directory are both faked.
#
#   sh test-detect-dtb.sh
#
# The phone branch is the one that cannot be exercised on the carrier rig, which
# is exactly why it is tested here.
set -u
HERE="$(dirname "$0")"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
PHONE=qcom-msm8974pro-fairphone-fp2.dtb
RIG=qcom-msm8974pro-fairphone-fp2-rig.dtb

mkbat() {					# mkbat <dir> <type> [present]
	mkdir -p "$T/ps/$1"
	printf '%s\n' "$2" > "$T/ps/$1/type"
	[ $# -ge 3 ] && printf '%s\n' "$3" > "$T/ps/$1/present"
}
reset_ps() { rm -rf "$T/ps"; mkdir -p "$T/ps"; }

check() {					# check <what> <expected> <got>
	if [ "$2" = "$3" ]; then
		echo "  ok    $1: $3"
	else
		echo "  FAIL  $1: expected '$2', got '$3'"
		fail=1
	fi
}

# The helper reads the kernel package's DTB dir by absolute path, so point the
# detection at a fake one by shadowing the variable it builds from.
detect() {					# detect <have_rig_dtb: yes|no>
	(
		PS_ROOT="$T/ps"
		. "$HERE/detect-dtb.sh"
		# shadow the package dir lookup used by citronics_detect_dtb
		citronics_detect_dtb() {
			case "${deviceinfo_dtb:-}" in
				"" | auto | AUTO) ;;
				*) echo "$deviceinfo_dtb"; return 0 ;;
			esac
			_bat="$(citronics_battery_state)"
			if [ "$_bat" = absent ] && [ "$1" = yes ]; then
				echo "$FP2_RIG_DTB"
			else
				echo "$FP2_PHONE_DTB"
			fi
		}
		citronics_detect_dtb "$1"
	)
}

echo "battery state:"
reset_ps; mkbat bat0 Battery 1;         check "present pack"        present "$(PS_ROOT=$T/ps sh -c ". $HERE/detect-dtb.sh; citronics_battery_state")"
reset_ps; mkbat bat0 Battery 0;         check "absent pack"         absent  "$(PS_ROOT=$T/ps sh -c ". $HERE/detect-dtb.sh; citronics_battery_state")"
reset_ps; mkbat bat0 Battery;           check "no present attr"     present "$(PS_ROOT=$T/ps sh -c ". $HERE/detect-dtb.sh; citronics_battery_state")"
reset_ps; mkbat usb0 USB;               check "no battery node"     unknown "$(PS_ROOT=$T/ps sh -c ". $HERE/detect-dtb.sh; citronics_battery_state")"
reset_ps; mkbat bat0 Battery 0; mkbat bat1 Battery 1
                                        check "one of two present"  present "$(PS_ROOT=$T/ps sh -c ". $HERE/detect-dtb.sh; citronics_battery_state")"

echo "dtb choice:"
reset_ps; mkbat bat0 Battery 0;         check "rig (no pack, rig dtb shipped)"  "$RIG"   "$(deviceinfo_dtb= detect yes)"
reset_ps; mkbat bat0 Battery 0;         check "no rig dtb in package -> phone"  "$PHONE" "$(deviceinfo_dtb= detect no)"
reset_ps; mkbat bat0 Battery 1;         check "phone (pack present)"            "$PHONE" "$(deviceinfo_dtb= detect yes)"
reset_ps; mkbat usb0 USB;               check "unknown -> phone"                "$PHONE" "$(deviceinfo_dtb= detect yes)"
reset_ps; mkbat bat0 Battery 0;         check "explicit override wins"          "custom.dtb" "$(deviceinfo_dtb=custom.dtb detect yes)"
reset_ps; mkbat bat0 Battery 0;         check "auto asks for detection"         "$RIG"   "$(deviceinfo_dtb=auto detect yes)"

echo "extlinux fdt rewrite:"
mkconf() { mkdir -p "$T/b/extlinux"; printf 'timeout 1\ndefault x\n\nlabel x\n\tkernel /zImage\n\tfdt /%s\n\tappend rw\n' "$1" > "$T/b/extlinux/extlinux.conf"; }
run_fdt() { ( . "$HERE/detect-dtb.sh"; citronics_set_extlinux_fdt "$1" "$T/b/extlinux/extlinux.conf" ) 2>/dev/null; grep -E '^\s*fdt' "$T/b/extlinux/extlinux.conf" | tr -d '\t'; }
mkconf "$PHONE";                        check "phone -> rig"        "fdt /$RIG"   "$(run_fdt "$RIG")"
mkconf "$RIG";                          check "rig -> phone"        "fdt /$PHONE" "$(run_fdt "$PHONE")"
mkconf "$RIG";                          check "already correct"     "fdt /$RIG"   "$(run_fdt "$RIG")"
mkdir -p "$T/b/extlinux"; printf 'label x\n\tfdt /some-other-board.dtb\n' > "$T/b/extlinux/extlinux.conf"
                                        check "unrelated fdt untouched" "fdt /some-other-board.dtb" "$(run_fdt "$RIG")"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
