#!/bin/bash
# Double-click once. Creates a self-signed code-signing certificate called
# "TrackpadTool Dev" in your login keychain, then rebuilds TrackpadTool with it.
# After this, macOS keeps TrackpadTool's Accessibility permission across rebuilds.
# macOS will ask for your password once, to trust the certificate for code signing.
set -euo pipefail
cd "$(dirname "$0")"
NAME="TrackpadTool Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "The \"$NAME\" certificate is already set up."
else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    echo "Creating the certificate…"
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -name "$NAME" -out "$TMP/cert.p12" -passout pass:trackpadtool
    security import "$TMP/cert.p12" -k "$KEYCHAIN" -P trackpadtool -T /usr/bin/codesign
    echo "Trusting it for code signing (macOS will ask for your password)…"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
    echo "Certificate ready."
fi

echo
echo "Rebuilding TrackpadTool with the certificate…"
bash ./build.sh --run

echo
echo "Last step, one time only:"
echo "System Settings › Privacy & Security › Accessibility:"
echo "remove TrackpadTool with –, then add it again with + (Documents/TrackpadTool/build)."
echo "From now on, rebuilds keep the permission."
