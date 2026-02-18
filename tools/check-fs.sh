#!/bin/bash
# Filesystem & SELinux compatibility check script for isabelle-core + Podman/MongoDB
# Usage: ./tools/check-fs.sh [path-to-check]
# Reports issues with permissions, SELinux relabeling support, xattr support.

set -euo pipefail

CHECK_PATH="${1:-$(pwd)}"
PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "============================================="
echo "  isabelle-core Filesystem Compatibility Check"
echo "  Path: ${CHECK_PATH}"
echo "============================================="
echo

# ── 1. Resolve and validate path ──────────────────────────────────────────────
echo "── Path Resolution ──────────────────────────"
if [ ! -e "${CHECK_PATH}" ]; then
	echo "${FAIL} Path does not exist: ${CHECK_PATH}"
	exit 1
fi
ABS_PATH="$(cd "${CHECK_PATH}" && pwd -P)"
echo "${INFO} Resolved path: ${ABS_PATH}"
echo

# ── 2. Filesystem type ────────────────────────────────────────────────────────
echo "── Filesystem Type ──────────────────────────"
FS_TYPE="$(stat -f --format="%T" "${ABS_PATH}" 2>/dev/null || df -T "${ABS_PATH}" | tail -1 | awk '{print $2}')"
MOUNT_POINT="$(df "${ABS_PATH}" | tail -1 | awk '{print $NF}')"
DEVICE="$(df "${ABS_PATH}" | tail -1 | awk '{print $1}')"

echo "${INFO} Device:	  ${DEVICE}"
echo "${INFO} Mount point: ${MOUNT_POINT}"
echo "${INFO} FS type:	 ${FS_TYPE}"

case "${FS_TYPE}" in
	ext4|xfs|btrfs|ext3|ext2)
		echo "${PASS} Filesystem ${FS_TYPE} supports xattrs and SELinux labels"
		XATTR_SUPPORTED=1
		;;
	nfs|nfs4|cifs|smb|smbfs)
		echo "${FAIL} Network filesystem (${FS_TYPE}) does NOT support xattrs - SELinux :Z relabeling will fail"
		XATTR_SUPPORTED=0
		;;
	tmpfs|ramfs)
		echo "${FAIL} tmpfs does NOT support persistent xattrs - SELinux :Z relabeling will fail"
		XATTR_SUPPORTED=0
		;;
	overlay|overlayfs)
		echo "${WARN} overlayfs has limited xattr support - SELinux :Z relabeling may fail"
		XATTR_SUPPORTED=0
		;;
	fuse*)
		echo "${WARN} FUSE filesystem (${FS_TYPE}) may not support xattrs - SELinux :Z relabeling may fail"
		XATTR_SUPPORTED=0
		;;
	*)
		echo "${WARN} Unknown filesystem type '${FS_TYPE}' - xattr support unknown"
		XATTR_SUPPORTED=0
		;;
esac
echo

# ── 3. Mount options (seclabel presence) ──────────────────────────────────────
echo "── Mount Options (SELinux seclabel) ─────────"
MOUNT_OPTS="$(findmnt --noheadings --output OPTIONS "${MOUNT_POINT}" 2>/dev/null || grep " ${MOUNT_POINT} " /proc/mounts | awk '{print $4}')"
echo "${INFO} Mount options: ${MOUNT_OPTS}"

if echo "${MOUNT_OPTS}" | grep -q 'seclabel'; then
	echo "${PASS} Mount has 'seclabel' - SELinux labeling is active on this filesystem"
	SECLABEL=1
else
	echo "${FAIL} Mount does NOT have 'seclabel' - SELinux :Z relabeling will silently do nothing"
	SECLABEL=0
fi
echo

# ── 4. xattr write test ───────────────────────────────────────────────────────
echo "── Extended Attribute (xattr) Write Test ────"
XATTR_TEST_FILE="${ABS_PATH}/.isabelle_xattr_test_$$"
touch "${XATTR_TEST_FILE}" 2>/dev/null && TOUCH_OK=1 || TOUCH_OK=0

if [ "${TOUCH_OK}" -eq 1 ]; then
	if setfattr -n user.isabelle_test -v "ok" "${XATTR_TEST_FILE}" 2>/dev/null; then
		VAL="$(getfattr -n user.isabelle_test --only-values "${XATTR_TEST_FILE}" 2>/dev/null || echo '')"
		if [ "${VAL}" = "ok" ]; then
			echo "${PASS} xattr write+read works on this path"
			XATTR_WORKS=1
		else
			echo "${FAIL} xattr write appeared to succeed but read returned wrong value"
			XATTR_WORKS=0
		fi
		setfattr -x user.isabelle_test "${XATTR_TEST_FILE}" 2>/dev/null || true
	else
		echo "${FAIL} xattr write failed (setfattr returned error) - SELinux :Z relabeling requires xattr support"
		XATTR_WORKS=0
	fi
	rm -f "${XATTR_TEST_FILE}"
else
	echo "${FAIL} Cannot create test file in ${ABS_PATH} - check write permissions"
	XATTR_WORKS=0
fi
echo

# ── 5. SELinux status ─────────────────────────────────────────────────────────
echo "── SELinux Status ───────────────────────────"
if command -v getenforce &>/dev/null; then
	SELINUX_STATUS="$(getenforce)"
	echo "${INFO} SELinux mode: ${SELINUX_STATUS}"
	case "${SELINUX_STATUS}" in
		Enforcing)
			echo "${WARN} SELinux is Enforcing - container bind mounts require correct labels"
			;;
		Permissive)
			echo "${WARN} SELinux is Permissive - denials logged but not enforced"
			;;
		Disabled)
			echo "${PASS} SELinux is Disabled - no relabeling issues"
			;;
	esac
else
	echo "${INFO} getenforce not found - SELinux may not be installed"
	SELINUX_STATUS="Unknown"
fi
echo

# ── 6. Current SELinux label on path ─────────────────────────────────────────
echo "── SELinux Label on Path ────────────────────"
# ls -ldZ format: PERMS LINKS OWNER GROUP LABEL PATH
# Extract the field matching SELinux context pattern (user:role:type:level)
RAW_LABEL="$(ls -ldZ "${ABS_PATH}" 2>/dev/null | awk '{
	for(i=1;i<=NF;i++) {
		if ($i ~ /^[a-z_]+:[a-z_]+:[a-z_]+/) { print $i; exit }
	}
}')"
if [ -n "${RAW_LABEL}" ]; then
	echo "${INFO} Current SELinux label: ${RAW_LABEL}"
	if echo "${RAW_LABEL}" | grep -qE '(unlabeled_t|default_t)'; then
		echo "${FAIL} Path has generic/unlabeled SELinux type - xattrs not stored (filesystem may not support them)"
	elif echo "${RAW_LABEL}" | grep -qE '(container_file_t|svirt_sandbox_file_t|container_ro_file_t)'; then
		echo "${PASS} Path already has container-compatible SELinux label"
	else
		echo "${WARN} Label '${RAW_LABEL}' is not a container type - :Z will attempt to relabel to container_file_t"
	fi
else
	echo "${INFO} No SELinux label detected (ls -Z not available or path unlabeled)"
fi
echo

# ── 7. Write permissions ──────────────────────────────────────────────────────
echo "── Write Permissions ────────────────────────"
STAT_PERMS="$(stat -c "%a %U %G" "${ABS_PATH}" 2>/dev/null)"
STAT_OWNER="$(echo "${STAT_PERMS}" | awk '{print $2}')"
STAT_GROUP="$(echo "${STAT_PERMS}" | awk '{print $3}')"
STAT_MODE="$(echo "${STAT_PERMS}" | awk '{print $1}')"
STAT_UID="$(stat -c "%u" "${ABS_PATH}" 2>/dev/null)"
echo "${INFO} Permissions: ${STAT_MODE}  Owner UID: ${STAT_UID} (${STAT_OWNER})  Group: ${STAT_GROUP}  Current user: $(whoami) ($(id -u))"
WRITE_TEST="${ABS_PATH}/.isabelle_write_test_$$"
if touch "${WRITE_TEST}" 2>/dev/null; then
	echo "${PASS} Directory is writable by current user ($(whoami))"
	rm -f "${WRITE_TEST}"
	WRITE_OK=1
else
	echo "${FAIL} Directory is NOT writable by current user ($(whoami))"
	if [ "${STAT_OWNER}" = "UNKNOWN" ]; then
		echo "${WARN} Owner UID ${STAT_UID} has no matching user - likely created inside a Podman user namespace"
		echo "${INFO} Fix: sudo chown $(id -u) ${ABS_PATH}"
		echo "${INFO}  or: podman unshare chown 0 ${ABS_PATH}  (if created by rootless Podman)"
	else
		echo "${INFO} Fix: sudo chown $(whoami) ${ABS_PATH}"
		echo "${INFO}  or: sudo chmod u+w ${ABS_PATH}"
		echo "${INFO}  or: sudo chmod o+w ${ABS_PATH}  (if container runs as different UID)"
	fi
	WRITE_OK=0
fi
echo

# ── 8. Podman-specific checks ─────────────────────────────────────────────────
echo "── Podman Availability ──────────────────────"
if command -v podman &>/dev/null; then
	PODMAN_VER="$(podman --version)"
	echo "${PASS} Podman found: ${PODMAN_VER}"

	# Check if rootless podman can see the path
	PODMAN_UNSHARE="$(podman unshare ls "${ABS_PATH}" 2>&1 | head -1)"
	if [ $? -eq 0 ]; then
		echo "${PASS} Podman (rootless) can access path in user namespace"
	else
		echo "${WARN} Podman (rootless) may have issues: ${PODMAN_UNSHARE}"
	fi
else
	echo "${INFO} Podman not found in PATH"
fi
echo

# ── 9. Recent SELinux denials for this path ───────────────────────────────────
echo "── Recent SELinux AVC Denials ───────────────"
if command -v ausearch &>/dev/null; then
	DENIALS="$(sudo ausearch -m avc -ts recent 2>/dev/null | grep -i "$(basename "${ABS_PATH}")" | head -5 || true)"
	if [ -n "${DENIALS}" ]; then
		echo "${FAIL} Recent SELinux denials found for this path:"
		echo "${DENIALS}"
	else
		echo "${PASS} No recent SELinux denials found for path (or ausearch requires sudo)"
	fi
elif [ -r /var/log/audit/audit.log ]; then
	DENIALS="$(grep "denied" /var/log/audit/audit.log | grep "$(basename "${ABS_PATH}")" | tail -5 || true)"
	if [ -n "${DENIALS}" ]; then
		echo "${FAIL} Audit log denials:"
		echo "${DENIALS}"
	else
		echo "${INFO} No denials in audit log for this path"
	fi
else
	echo "${INFO} ausearch not available and /var/log/audit/audit.log not readable"
	echo "${INFO} Run: sudo ausearch -m avc -ts recent | grep $(basename "${ABS_PATH}")"
fi
echo

# ── 10. Summary & recommendation ─────────────────────────────────────────────
echo "============================================="
echo "  Summary"
echo "============================================="

ISSUES=0

# Write permission is always a blocker - check it first
if [ "${WRITE_OK:-0}" -eq 0 ]; then
	echo "${FAIL} WRITE PERMISSIONS BLOCKED - fix this first before worrying about containers"
	if [ "${STAT_OWNER:-UNKNOWN}" = "UNKNOWN" ]; then
		echo "	  The directory owner UID ${STAT_UID} has no host user mapping."
		echo "	  This often happens when Podman (rootless) created the directory."
		echo "	  Fix:"
		echo "		sudo chown $(id -u) ${ABS_PATH}"
		echo "		# or if created inside rootless Podman container:"
		echo "		podman unshare chown 0 ${ABS_PATH}"
	else
		echo "	  Fix: sudo chown $(whoami) ${ABS_PATH}"
	fi
	echo
	ISSUES=$((ISSUES + 1))
fi

# SELinux label assessment (only meaningful if write OK or for container bind mount)
if [ -n "${RAW_LABEL:-}" ] && echo "${RAW_LABEL}" | grep -qE '(container_file_t|svirt_sandbox_file_t)'; then
	echo "${PASS} SELinux label is already container-compatible (${RAW_LABEL})"
	echo "	  Bind mount WITHOUT :Z is safe (label already correct)"
	echo "	  Recommendation: -v ${ABS_PATH}:/data/db"
elif [ "${SECLABEL:-0}" -eq 1 ] && [ "${XATTR_WORKS:-0}" -eq 1 ]; then
	echo "${WARN} SELinux label needs relabeling for container access"
	echo "	  Recommendation: -v ${ABS_PATH}:/data/db:Z"
elif [ "${SECLABEL:-0}" -eq 0 ]; then
	echo "${FAIL} Filesystem does not support SELinux seclabel - :Z will not work"
	echo "	  Recommendation: --security-opt label=disabled"
	ISSUES=$((ISSUES + 1))
fi

if [ "${ISSUES}" -eq 0 ] && [ "${WRITE_OK:-1}" -eq 1 ]; then
	echo
	echo "${PASS} No blocking issues found"
	echo "	  Podman bind mount should work correctly"
fi
echo
