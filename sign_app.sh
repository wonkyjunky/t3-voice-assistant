#!/bin/bash
# sign_app.sh APP IDENTIFIER
# Signs APP with the local identity "Voice Assistant Local Signing" (see make_signing_identity.sh), so
# macOS keeps the app's permissions across rebuilds. Without that identity it signs ad hoc, as
# before, and says so: macOS then asks for the permissions again after each rebuild.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=signing_env.sh
source "$HERE/signing_env.sh"

APP="$1"
IDENTIFIER="$2"

if [ -f "$SIGNING_KEYCHAIN" ] &&
  password="$(security find-generic-password -s "$SIGNING_PASSWORD_SERVICE" -w ${SIGNING_PASSWORD_STORE:+"$SIGNING_PASSWORD_STORE"} 2>/dev/null)"; then
  # On standard input, never on a command line (see make_signing_identity.sh).
  printf 'unlock-keychain -p %s "%s"\n' "$password" "$SIGNING_KEYCHAIN" | security -i >/dev/null
  codesign -s "$SIGNING_IDENTITY" --keychain "$SIGNING_KEYCHAIN" -f --identifier "$IDENTIFIER" "$APP"
  echo "signed with $SIGNING_IDENTITY"
else
  echo "no local signing identity (run make_signing_identity.sh); signing ad hoc" >&2
  codesign -s - -f --identifier "$IDENTIFIER" "$APP"
fi
