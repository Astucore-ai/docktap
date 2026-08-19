#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN="$ROOT/signing"
KEYCHAIN="$SIGN/docktap.keychain-db"
P12="$SIGN/docktap.p12"
CERT="$SIGN/docktap.cer"
CN="Docktap"
PASSWORD="docktap-local-sign"

mkdir -p "$SIGN"

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$PASSWORD" "$KEYCHAIN"
fi
security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"

if ! security find-identity -v "$KEYCHAIN" 2>/dev/null | grep -q "$CN"; then
  TMP="$(mktemp -d)"
  cat > "$TMP/cert.cnf" <<'EOF'
[ req ]
default_bits       = 2048
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = Docktap
O = Docktap

[ v3 ]
basicConstraints    = critical,CA:FALSE
keyUsage            = critical,digitalSignature
extendedKeyUsage    = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.cnf" -extensions v3 >/dev/null 2>&1
  cp "$TMP/cert.pem" "$CERT"
  openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$P12" -passout pass:"$PASSWORD" \
    -name "$CN" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1
  security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" \
    -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
  # Trusting the cert as a root needs an admin dialog. Skip unless asked —
  # build.sh falls back to another local identity (or ad-hoc) if this one
  # is not yet valid for codesign.
  if [[ "${DOCKTAP_TRUST_CERT:-}" == "1" ]]; then
    security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
  fi
  rm -rf "$TMP"
fi

echo "$KEYCHAIN"
