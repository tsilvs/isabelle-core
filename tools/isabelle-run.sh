#!/usr/bin/env bash
# isabelle-run.sh - Build and run isabelle-core for local development/testing
#
# Usage:
#   ./tools/isabelle-run.sh [OPTIONS]
#
# Options:
#   --prefix PATH        Base directory containing isabelle-core and data dirs
#                        (default: ./$(id -un))
#   --db NAME            MongoDB database name (default: intranet)
#   --data-source PATH   Source data directory to symlink as <prefix>/data-<db>
#                        (default: ./interpretica-io/<db>-data)
#   --plugin-dir PATH    Plugin directory (default: .)
#   --db-url URL         MongoDB URL (default: mongodb://localhost:27017)
#   --pub-url URL        Public URL (default: http://localhost:8081)
#   --port PORT          Bind port (default: 8090)
#   --build              Build isabelle-core before running (default: auto-detect)
#   --no-build           Skip build step
#   --first-run          Import data from local files into MongoDB, then exit
#   --cookie-http-insecure  Allow insecure cookies (use for local dev)
#   --help               Show this help

set -euo pipefail

CALLER_DIR="$(pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
PREFIX=""
DB="intranet"
DATA_SOURCE=""
PLUGIN_DIR="."
DB_URL="mongodb://127.0.0.1:27017"
PUB_URL="http://localhost:8081"
PORT="8090"
BUILD="auto"
FIRST_RUN=""
COOKIE_HTTP_INSECURE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix)
			PREFIX="$2"; shift ;;
		--db)
			DB="$2"; shift ;;
		--data-source)
			DATA_SOURCE="$2"; shift ;;
		--plugin-dir)
			PLUGIN_DIR="$2"; shift ;;
		--db-url)
			DB_URL="$2"; shift ;;
		--pub-url)
			PUB_URL="$2"; shift ;;
		--port)
			PORT="$2"; shift ;;
		--build)
			BUILD="yes" ;;
		--no-build)
			BUILD="no" ;;
		--first-run)
			FIRST_RUN="--first-run" ;;
		--cookie-http-insecure)
			COOKIE_HTTP_INSECURE="--cookie-http-insecure" ;;
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
DEFAULT_PREFIX="${CALLER_DIR}/$(id -un)"
PREFIX="${PREFIX:-${DEFAULT_PREFIX}}"
# Resolve to absolute path
if [[ "${PREFIX}" != /* ]]; then
	PREFIX="${CALLER_DIR}/${PREFIX}"
fi
PREFIX="$(cd "${PREFIX}" 2>/dev/null && pwd -P || { mkdir -p "${PREFIX}" && cd "${PREFIX}" && pwd -P; })"

ISABELLE_CORE_DIR="${PREFIX}/isabelle-core"
DATA_LINK="${PREFIX}/data-${DB}"

# Resolve data source
if [ -z "${DATA_SOURCE}" ]; then
	DATA_SOURCE="${CALLER_DIR}/interpretica-io/${DB}-data"
fi
if [[ "${DATA_SOURCE}" != /* ]]; then
	DATA_SOURCE="${CALLER_DIR}/${DATA_SOURCE}"
fi

# Resolve plugin-dir
if [[ "${PLUGIN_DIR}" != /* ]]; then
	PLUGIN_DIR="${CALLER_DIR}/${PLUGIN_DIR}"
fi

echo "============================================="
echo "  isabelle-core Run Wrapper"
echo "  prefix:      ${PREFIX}"
echo "  core dir:    ${ISABELLE_CORE_DIR}"
echo "  data source: ${DATA_SOURCE}"
echo "  data link:   ${DATA_LINK}"
echo "  database:    ${DB}"
echo "  db-url:      ${DB_URL}"
echo "  pub-url:     ${PUB_URL}"
echo "  port:        ${PORT}"
echo "  plugin-dir:  ${PLUGIN_DIR}"
echo "  build:       ${BUILD}"
echo "  first-run:   ${FIRST_RUN:-no}"
echo "============================================="
echo

# ── Validate core directory ───────────────────────────────────────────────────
if [ ! -d "${ISABELLE_CORE_DIR}" ]; then
	echo "ERROR: isabelle-core directory not found: ${ISABELLE_CORE_DIR}" >&2
	echo "       Set --prefix to the parent directory containing isabelle-core" >&2
	exit 1
fi

if [ ! -f "${ISABELLE_CORE_DIR}/run.sh" ]; then
	echo "ERROR: run.sh not found in ${ISABELLE_CORE_DIR}" >&2
	exit 1
fi

# ── Create data symlink ───────────────────────────────────────────────────────
if [ ! -e "${DATA_LINK}" ]; then
	if [ ! -e "${DATA_SOURCE}" ]; then
		echo "WARNING: data source does not exist: ${DATA_SOURCE}" >&2
		echo "         Skipping symlink creation. Pass --data-source to specify the path." >&2
	else
		echo "── Creating data symlink"
		# -r: relative symlink (correct path resolution regardless of cwd)
		# -s: symbolic link
		# -f: force overwrite if exists
		ln -rsf "${DATA_SOURCE}" "${DATA_LINK}"
		echo "   ${DATA_LINK} -> ${DATA_SOURCE}"
		echo
	fi
else
	echo "── Data link already exists: ${DATA_LINK}"
	if [ -L "${DATA_LINK}" ]; then
		echo "   -> $(readlink "${DATA_LINK}")"
	fi
	echo
fi

# ── Build ─────────────────────────────────────────────────────────────────────
if [ "${BUILD}" = "auto" ]; then
	# Auto-detect: build if no binary found
	if [ ! -f "${ISABELLE_CORE_DIR}/target/debug/isabelle-core" ] && \
	[ ! -f "${ISABELLE_CORE_DIR}/isabelle-core" ]; then
		BUILD="yes"
	else
		BUILD="no"
	fi
fi

if [ "${BUILD}" = "yes" ]; then
	echo "── Building isabelle-core"
	(cd "${ISABELLE_CORE_DIR}" && make)
	echo
fi

# ── Stop existing instance ────────────────────────────────────────────────────
echo "── Stopping existing isabelle-core (if any)"
killall isabelle-core 2>/dev/null && echo "   Stopped" || echo "   Not running"
echo

# ── Run isabelle-core ─────────────────────────────────────────────────────────
echo "── Starting isabelle-core"
echo

"${ISABELLE_CORE_DIR}/run.sh" \
	--data-path "${DATA_LINK}" \
	--database "${DB}" \
	--db-url "${DB_URL}" \
	--pub-url "${PUB_URL}" \
	--port "${PORT}" \
	--plugin-dir "${PLUGIN_DIR}" \
	${COOKIE_HTTP_INSECURE} \
	${FIRST_RUN}
