#!/bin/bash
set -euo pipefail
umask 077

# Keep the identity outside the checkout so new clones reuse the same certificate.
SIGNING_DIR="${SNAPX_SIGNING_CONFIG_DIR:-$HOME/Library/Application Support/SnapX/Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
CERT="$SIGNING_DIR/SnapX-Dev.pem"
IDENTITY_FILE="$SIGNING_DIR/identity.sha1"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ ! -f "$CERT" ]]; then
  if security find-certificate -c 'SnapX Dev' -p "$KEYCHAIN" > "$SIGNING_DIR/existing.pem" 2>/dev/null; then
    mv "$SIGNING_DIR/existing.pem" "$CERT"
  else
    rm -f "$SIGNING_DIR/existing.pem"
    task_temp=$(mktemp -d "$SIGNING_DIR/setup.XXXXXX")
    trap 'rm -rf "$task_temp"' EXIT
    cat > "$task_temp/certificate.conf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = SnapX Dev
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
    openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
      -config "$task_temp/certificate.conf" \
      -keyout "$task_temp/private.pem" -out "$task_temp/certificate.pem" 2>/dev/null
    # Import credentials and key material exist only in this owner-only temporary directory.
    openssl rand -base64 32 > "$task_temp/import-password"
    openssl pkcs12 -export -inkey "$task_temp/private.pem" -in "$task_temp/certificate.pem" \
      -name 'SnapX Dev' -passout "file:$task_temp/import-password" -out "$task_temp/identity.p12"
    security import "$task_temp/identity.p12" -k "$KEYCHAIN" -P "$(cat "$task_temp/import-password")" -T /usr/bin/codesign
    cp "$task_temp/certificate.pem" "$CERT"
  fi
fi

fingerprint=$(openssl x509 -in "$CERT" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
if [[ -f "$IDENTITY_FILE" && "$(cat "$IDENTITY_FILE")" != "$fingerprint" ]]; then
  echo 'Signing identity mismatch; refusing to replace the pinned identity.' >&2
  exit 1
fi
# User-level trust, restricted to code signing; no TLS trust or system trust changes.
if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$fingerprint"; then
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT"
fi
if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$fingerprint"; then
  echo 'Certificate is present, but its usable private key is missing or trust was not approved.' >&2
  echo 'Restore the original signing identity in Keychain Access; do not generate a replacement.' >&2
  exit 1
fi
printf '%s\n' "$fingerprint" > "$IDENTITY_FILE"
echo "Fixed signing identity: $fingerprint"
echo "Configuration: $SIGNING_DIR"
