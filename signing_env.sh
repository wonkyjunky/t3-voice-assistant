# Shared names for the local code signing identity (sourced by make_signing_identity.sh and
# sign_app.sh). Signing every build with the same certificate keeps the apps' code requirement the
# same, so macOS keeps their microphone and speech permissions across rebuilds.
# The values can be overridden from the environment for tests.
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/voice-assistant-signing.keychain-db}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Voice Assistant Local Signing}"
# The signing keychain's password lives in the login Keychain under this service, never in a file.
SIGNING_PASSWORD_SERVICE="${SIGNING_PASSWORD_SERVICE:-voice-assistant-signing-keychain}"
# Where that password item lives: empty means the login Keychain.
SIGNING_PASSWORD_STORE="${SIGNING_PASSWORD_STORE:-}"
