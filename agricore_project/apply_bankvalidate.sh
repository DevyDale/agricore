#!/usr/bin/env bash
set -euo pipefail

FW="utils/flutterwave.py"
SER="escrow/api/serializers.py"

BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ -n "$BR" ] && [ "$BR" != "dev" ]; then
  echo ">> Refusing: current branch is '$BR', not 'dev'."; exit 1
fi
for f in "$FW" "$SER"; do
  [ -f "$f" ] || { echo ">> Not found: $f (run from the Django root)"; exit 1; }
done

TS="$(date +%Y%m%d-%H%M%S)"
BK="bankvalidate_backup_${TS}"
mkdir -p "$BK/utils" "$BK/escrow/api"
cp -a "$FW" "$BK/utils/flutterwave.py"
cp -a "$SER" "$BK/escrow/api/serializers.py"
echo ">> Backup: $BK/"

set +e
python3 - "$FW" "$SER" <<'PYEOF'
import sys, ast, base64
FW, SER = sys.argv[1], sys.argv[2]
fw_block = base64.b64decode("CgpfQkFOS1NfQ0FDSEUgPSB7fQoKCmRlZiBsaXN0X2JhbmtzKGNvdW50cnk9IlVHIik6CiAgICAiIiJGbHV0dGVyd2F2ZSdzIHN1cHBvcnRlZCBiYW5rcyBmb3IgYSBjb3VudHJ5IGFzCiAgICBbeyJjb2RlIjogc3RyLCAibmFtZSI6IHN0cn0sIC4uLl0sIHNvcnRlZCBieSBuYW1lLiBDYWNoZWQgcGVyIHByb2Nlc3MKICAgICh0aGUgbGlzdCByYXJlbHkgY2hhbmdlcykuIFJhaXNlcyBGbHV0dGVyd2F2ZUVycm9yIG9uIGEgZ2F0ZXdheSBmYWlsdXJlLiIiIgogICAgY291bnRyeSA9IChjb3VudHJ5IG9yICJVRyIpLnVwcGVyKCkKICAgIGNhY2hlZCA9IF9CQU5LU19DQUNIRS5nZXQoY291bnRyeSkKICAgIGlmIGNhY2hlZCBpcyBub3QgTm9uZToKICAgICAgICByZXR1cm4gY2FjaGVkCiAgICB0cnk6CiAgICAgICAgcmVzcCA9IHJlcXVlc3RzLmdldChmIntGTFdfQkFTRX0vYmFua3Mve2NvdW50cnl9IiwgaGVhZGVycz1faGVhZGVycygpLCB0aW1lb3V0PTMwKQogICAgZXhjZXB0IHJlcXVlc3RzLlJlcXVlc3RFeGNlcHRpb24gYXMgZToKICAgICAgICByYWlzZSBGbHV0dGVyd2F2ZUVycm9yKHN0cihlKSkKICAgIGRhdGEgPSBfaGFuZGxlKHJlc3ApCiAgICBiYW5rcyA9IFsKICAgICAgICB7ImNvZGUiOiBzdHIoYi5nZXQoImNvZGUiKSBvciAiIiksICJuYW1lIjogYi5nZXQoIm5hbWUiKSBvciAiIn0KICAgICAgICBmb3IgYiBpbiAoZGF0YS5nZXQoImRhdGEiKSBvciBbXSkKICAgICAgICBpZiBiLmdldCgiY29kZSIpCiAgICBdCiAgICBiYW5rcy5zb3J0KGtleT1sYW1iZGEgYjogYlsibmFtZSJdKQogICAgaWYgYmFua3M6CiAgICAgICAgX0JBTktTX0NBQ0hFW2NvdW50cnldID0gYmFua3MKICAgIHJldHVybiBiYW5rcwo=").decode("utf-8")
ser_old  = base64.b64decode("ICAgICAgICBlbHNlOgogICAgICAgICAgICBpZiBub3QgbnVtYmVyOgogICAgICAgICAgICAgICAgcmFpc2Ugc2VyaWFsaXplcnMuVmFsaWRhdGlvbkVycm9yKHsiYWNjb3VudF9udW1iZXIiOiAiQmFuayBhY2NvdW50IG51bWJlciBpcyByZXF1aXJlZC4ifSkKICAgICAgICAgICAgaWYgbm90IChjdXIoImFjY291bnRfYmFuayIsICIiKSBvciAiIikuc3RyaXAoKToKICAgICAgICAgICAgICAgIHJhaXNlIHNlcmlhbGl6ZXJzLlZhbGlkYXRpb25FcnJvcih7ImFjY291bnRfYmFuayI6ICJCYW5rIGNvZGUgaXMgcmVxdWlyZWQgZm9yIGJhbmsgcGF5b3V0cy4ifSkKICAgICAgICByZXR1cm4gYXR0cnMK").decode("utf-8")
ser_new  = base64.b64decode("ICAgICAgICBlbHNlOgogICAgICAgICAgICBpZiBub3QgbnVtYmVyOgogICAgICAgICAgICAgICAgcmFpc2Ugc2VyaWFsaXplcnMuVmFsaWRhdGlvbkVycm9yKHsiYWNjb3VudF9udW1iZXIiOiAiQmFuayBhY2NvdW50IG51bWJlciBpcyByZXF1aXJlZC4ifSkKICAgICAgICAgICAgY29kZSA9IChjdXIoImFjY291bnRfYmFuayIsICIiKSBvciAiIikuc3RyaXAoKQogICAgICAgICAgICBpZiBub3QgY29kZToKICAgICAgICAgICAgICAgIHJhaXNlIHNlcmlhbGl6ZXJzLlZhbGlkYXRpb25FcnJvcih7ImFjY291bnRfYmFuayI6ICJCYW5rIGNvZGUgaXMgcmVxdWlyZWQgZm9yIGJhbmsgcGF5b3V0cy4ifSkKICAgICAgICAgICAgZnJvbSB1dGlscyBpbXBvcnQgZmx1dHRlcndhdmUKICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgdmFsaWRfY29kZXMgPSB7YlsiY29kZSJdIGZvciBiIGluIGZsdXR0ZXJ3YXZlLmxpc3RfYmFua3MoIlVHIil9CiAgICAgICAgICAgIGV4Y2VwdCBmbHV0dGVyd2F2ZS5GbHV0dGVyd2F2ZUVycm9yOgogICAgICAgICAgICAgICAgdmFsaWRfY29kZXMgPSBzZXQoKQogICAgICAgICAgICBpZiB2YWxpZF9jb2RlcyBhbmQgY29kZSBub3QgaW4gdmFsaWRfY29kZXM6CiAgICAgICAgICAgICAgICByYWlzZSBzZXJpYWxpemVycy5WYWxpZGF0aW9uRXJyb3IoCiAgICAgICAgICAgICAgICAgICAgeyJhY2NvdW50X2JhbmsiOiAiU2VsZWN0IGEgdmFsaWQgYmFuayBmcm9tIHRoZSBsaXN0LiJ9CiAgICAgICAgICAgICAgICApCiAgICAgICAgICAgIGF0dHJzWyJhY2NvdW50X2JhbmsiXSA9IGNvZGUKICAgICAgICByZXR1cm4gYXR0cnMK").decode("utf-8")

# 1) flutterwave.py: add list_banks (idempotent)
src = open(FW, encoding="utf-8").read()
if "def list_banks(" in src:
    print("   flutterwave.py: list_banks already present, skip")
else:
    new = src.rstrip("\n") + "\n" + fw_block
    try:
        ast.parse(new)
    except SyntaxError as e:
        print("   ERROR flutterwave.py would not parse: %s" % e); sys.exit(2)
    open(FW, "w", encoding="utf-8").write(new)
    print("   OK flutterwave.py: list_banks() added")

# 2) serializers.py: validate bank code against Flutterwave list (idempotent)
src2 = open(SER, encoding="utf-8").read()
if "Select a valid bank from the list." in src2:
    print("   serializers.py: bank-code validation already present, skip")
else:
    if ser_old not in src2:
        print("   ERROR serializers.py: expected bank-branch anchor not found; aborting"); sys.exit(4)
    new2 = src2.replace(ser_old, ser_new, 1)
    try:
        ast.parse(new2)
    except SyntaxError as e:
        print("   ERROR serializers.py would not parse: %s" % e); sys.exit(3)
    open(SER, "w", encoding="utf-8").write(new2)
    print("   OK serializers.py: bank code now checked against Flutterwave's bank list")
PYEOF
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo ">> Patch failed (rc=$rc). Restoring backup."
  cp -a "$BK/utils/flutterwave.py" "$FW"
  cp -a "$BK/escrow/api/serializers.py" "$SER"
  exit "$rc"
fi

echo "DONE"
echo
echo ">> Restart the server. No migration needed."
echo ">> Rollback: cp -a $BK/utils/flutterwave.py $FW && cp -a $BK/escrow/api/serializers.py $SER"
