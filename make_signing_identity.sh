#!/bin/bash
# One time: makes the self-signed code signing identity "Voice Assistant Local Signing" in its own keychain
# (~/Library/Keychains/voice-assistant-signing.keychain-db), used by sign_app.sh for AssistantListen.app and
# AssistantAvatar.app. The certificate does not need to be trusted: codesign accepts it, and macOS
# then identifies the app by its identifier and this certificate, the same after every rebuild.
#
# The keychain is not added to the keychain search list. Its random password is kept in the login
# Keychain (service voice-assistant-signing-keychain). Passwords never appear on a command line:
# they reach security and openssl on standard input, written by the shell's built-in printf, so
# other processes cannot read them from the process list. The certificate files are made in a
# temporary folder and removed. Does nothing when the keychain already exists.
#
# Undo:
#   security delete-keychain ~/Library/Keychains/voice-assistant-signing.keychain-db
#   security delete-generic-password -s voice-assistant-signing-keychain

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=signing_env.sh
source "$HERE/signing_env.sh"
VALID_DAYS=3650

if [ -f "$SIGNING_KEYCHAIN" ]; then
  echo "already exists: $SIGNING_KEYCHAIN"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Hex only, so the passwords need no quoting in the security commands below.
password="$(openssl rand -hex 24)"
p12_password="$(openssl rand -hex 24)"

cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGNING_IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" \
  -days "$VALID_DAYS" -config "$work/cert.cnf" 2>/dev/null
printf '%s\n' "$p12_password" | openssl pkcs12 -export -legacy -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/id.p12" -passout stdin 2>/dev/null

# security -i reads its commands from standard input, so none of these passwords is an argument.
printf '%s\n' \
  "add-generic-password -U -a \"$USER\" -s \"$SIGNING_PASSWORD_SERVICE\" -w $password ${SIGNING_PASSWORD_STORE:+\"$SIGNING_PASSWORD_STORE\"}" \
  "create-keychain -p $password \"$SIGNING_KEYCHAIN\"" \
  "unlock-keychain -p $password \"$SIGNING_KEYCHAIN\"" \
  "import \"$work/id.p12\" -k \"$SIGNING_KEYCHAIN\" -P $p12_password -T /usr/bin/codesign" \
  "set-key-partition-list -S apple-tool:,apple: -s -k $password \"$SIGNING_KEYCHAIN\"" |
  security -i >/dev/null
security set-keychain-settings "$SIGNING_KEYCHAIN"

security find-identity -p codesigning "$SIGNING_KEYCHAIN" | grep -q "$SIGNING_IDENTITY"
echo "made $SIGNING_IDENTITY in $SIGNING_KEYCHAIN"
