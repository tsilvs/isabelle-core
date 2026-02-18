#!/usr/bin/env bash
# mongo-setup.sh - Set up and run a MongoDB OCI container for isabelle-core
#
# Usage:
#   ./tools/mongo-setup.sh [OPTIONS]
#
# Options:
#   --prefix PATH        Base directory for data/logs (default: ./$(id -un))
#   --prefix-logs PATH   Base directory for logs (default: same as --prefix)
#   --db NAME            Database/container name (default: intranet)
#   --port PORT          Host port to publish (default: 27017)
#   --image IMAGE        OCI image to use (default: docker.io/library/mongo:7.0)
#   --detach             Run container in background (default: foreground)
#   --no-recreate        Skip stop/rm if container doesn't exist (don't fail)
#   --logappend          Pass --logappend to mongod inside container
#   --help               Show this help
#
# BEFORE RUNNING: verify filesystem permissions with:
#   ./tools/check-fs.sh <prefix>/<db>-data

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_PREFIX="./$(id -un)"
PREFIX=""
PREFIX_LOGS=""
DB="intranet"
PORT="27017"
IMAGE="docker.io/library/mongo:7.0"
DETACH=""
NO_RECREATE=0
LOGAPPEND=0

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix)
			PREFIX="$2"; shift ;;
		--prefix-logs)
			PREFIX_LOGS="$2"; shift ;;
		--db)
			DB="$2"; shift ;;
		--port)
			PORT="$2"; shift ;;
		--image)
			IMAGE="$2"; shift ;;
		--detach)
			DETACH="--detach" ;;
		--no-recreate)
			NO_RECREATE=1 ;;
		--logappend)
			LOGAPPEND=1 ;;
		--help)
			sed -n '/^# Usage:/,/^[^#]/p' "$0" | head -n -1 | sed 's/^# \?//'
			exit 0 ;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1 ;;
	esac
	shift
done

# ── Resolve paths ──────────────────────────────────────────────────────────────
PREFIX="${PREFIX:-${DEFAULT_PREFIX}}"
PREFIX_LOGS="${PREFIX_LOGS:-${PREFIX}}"

# Resolve to absolute paths
PREFIX="$(cd "$(dirname "${PREFIX}")" 2>/dev/null && pwd)/$(basename "${PREFIX}")"
PREFIX_LOGS="$(cd "$(dirname "${PREFIX_LOGS}")" 2>/dev/null && pwd)/$(basename "${PREFIX_LOGS}")"

DATA_DIR="${PREFIX}/${DB}-data"
LOGS_DIR="${PREFIX_LOGS}/${DB}-logs"
CONTAINER_NAME="mongo-${DB}"

echo "============================================="
echo "  MongoDB OCI Container Setup"
echo "  DB:         ${DB}"
echo "  Data:       ${DATA_DIR}"
echo "  Logs:       ${LOGS_DIR}"
echo "  Container:  ${CONTAINER_NAME}"
echo "  Port:       ${PORT}:27017 (IPv4+IPv6)"
echo "  Image:      ${IMAGE}"
echo "============================================="
echo

# ── Verify filesystem before proceeding ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "${SCRIPT_DIR}/check-fs.sh" ]; then
	echo "── Pre-flight filesystem check ──────────────"
	# Only check if data dir already exists
	if [ -d "${DATA_DIR}" ]; then
		"${SCRIPT_DIR}/check-fs.sh" "${DATA_DIR}" || {
			echo
			echo "WARNING: Filesystem check reported issues. Proceeding anyway."
			echo "         Run ./tools/check-fs.sh ${DATA_DIR} to review."
		}
	fi
	echo
fi

# ── Prepare data directory ────────────────────────────────────────────────────
echo "── Preparing data directory: ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
# Transfer ownership back to host user (recovers from previous container mapping)
sudo chown "$(id -u)" "${DATA_DIR}"
# Make world-writable: MongoDB entrypoint (UID 0) and mongod (UID 999) must both write.
# Podman rootless maps these to different host UIDs, so 777 is simplest.
# SELinux :Z on the podman run command handles access control at the MAC layer.
chmod 777 "${DATA_DIR}"
echo "   Done: ${DATA_DIR}"
echo

# ── Prepare logs directory ────────────────────────────────────────────────────
echo "── Preparing logs directory: ${LOGS_DIR}"
mkdir -p "${LOGS_DIR}"
sudo chown "$(id -u)" "${LOGS_DIR}"
chmod 777 "${LOGS_DIR}"
echo "   Done: ${LOGS_DIR}"
echo

# ── Stop and remove existing container ────────────────────────────────────────
echo "── Vacating container name: ${CONTAINER_NAME}"
if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
	podman stop "${CONTAINER_NAME}" && podman rm "${CONTAINER_NAME}"
	echo "   Stopped and removed existing container"
else
	echo "   No existing container found"
fi
echo

# ── Build mongod extra args ────────────────────────────────────────────────────
# Always bind to all IPv4 and IPv6 interfaces so clients can reach the container
# regardless of whether their system resolves "localhost" to 127.0.0.1 or ::1.
MONGOD_ARGS="--ipv6 --bind_ip_all"
if [ "${LOGAPPEND}" -eq 1 ]; then
	MONGOD_ARGS="${MONGOD_ARGS} --logappend"
fi

# ── Run the container ─────────────────────────────────────────────────────────
echo "── Starting container: ${CONTAINER_NAME}"
echo

# :Z relabels the bind mount with the NEW container's MCS SELinux categories.
# Without :Z, the old container's categories (c195,c544 etc.) remain and deny access.
podman run \
	--publish "${PORT}:27017" \
	--name "${CONTAINER_NAME}" \
	--volume "${DATA_DIR}:/data/db:Z" \
	--volume "${LOGS_DIR}:/var/log/mongodb:Z" \
	${DETACH} \
	"${IMAGE}" \
	${MONGOD_ARGS}

if [ -n "${DETACH}" ]; then
	echo
	echo "Container started in background."
	echo "Logs: podman logs -f ${CONTAINER_NAME}"
	echo "Stop: podman stop ${CONTAINER_NAME}"
fi
