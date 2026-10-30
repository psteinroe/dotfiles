#!/usr/bin/env bash
set -euo pipefail
# Run from the Mac: ./bootstrap-remote.sh USER@HOST [--home-manager]
# The target must already exist, with SSH access as its development user.
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$root/bin/remote" setup "$@"
