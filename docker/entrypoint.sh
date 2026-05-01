#!/bin/sh
set -e
export HOME="${HOME:-/tmp}"
mkdir -p "$HOME" 2>/dev/null || true
exec "$@"
