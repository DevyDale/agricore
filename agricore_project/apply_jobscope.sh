#!/usr/bin/env bash
set -euo pipefail
TGT="logistics/api/views.py"
BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ -n "$BR" ] && [ "$BR" != "dev" ]; then echo ">> Refusing: on '$BR', not 'dev'."; exit 1; fi
[ -f "$TGT" ] || { echo ">> Not found: $TGT (run from Django root)"; exit 1; }
TS="$(date +%Y%m%d-%H%M%S)"; BK="jobscope_backup_${TS}"; mkdir -p "$BK/logistics/api"
cp -a "$TGT" "$BK/logistics/api/views.py"; echo ">> Backup: $BK/"
set +e
python3 - "$TGT" <<'PYEOF'
import sys, ast, base64
p=sys.argv[1]; src=open(p,encoding="utf-8").read()
old=base64.b64decode("ICAgICAgICBpZiBzY29wZSA9PSAibWluZV90cmFuc3BvcnRlciI6CiAgICAgICAgICAgIHJldHVybiBxcy5maWx0ZXIodHJhbnNwb3J0ZXJfX3VzZXI9dXNlcikKICAgICAgICByZXR1cm4gcXMuZmlsdGVyKFEoY3JlYXRlZF9ieT11c2VyKSB8IFEodHJhbnNwb3J0ZXJfX3VzZXI9dXNlcikpLmRpc3RpbmN0KCkK").decode(); new=base64.b64decode("ICAgICAgICBpZiBzY29wZSA9PSAibWluZV90cmFuc3BvcnRlciI6CiAgICAgICAgICAgIHJldHVybiBxcy5maWx0ZXIodHJhbnNwb3J0ZXJfX3VzZXI9dXNlcikKICAgICAgICAjIERldGFpbCBhY3Rpb25zIG11c3QgcmVzb2x2ZSBhbiBvcGVuIGpvYiBhIHJpZGVyIGRvZXMgbm90IHlldCBvd24gKHNvIGEKICAgICAgICAjIHJpZGVyIGNhbiB2aWV3L2FjY2VwdCBpdCk7IGxpc3Qgc3RheXMgc2NvcGVkIHRvIG93biArIGFzc2lnbmVkIGpvYnMuCiAgICAgICAgaWYgZ2V0YXR0cihzZWxmLCAiYWN0aW9uIiwgTm9uZSkgaW4gKCJyZXRyaWV2ZSIsICJhY2NlcHQiLCAicGlja3VwIiwgImNhbmNlbCIsICJzZW5kX2xpbmsiKToKICAgICAgICAgICAgcmV0dXJuIHFzLmZpbHRlcigKICAgICAgICAgICAgICAgIFEoY3JlYXRlZF9ieT11c2VyKSB8IFEodHJhbnNwb3J0ZXJfX3VzZXI9dXNlcikgfCBRKHN0YXR1cz0ib3BlbiIpCiAgICAgICAgICAgICkuZGlzdGluY3QoKQogICAgICAgIHJldHVybiBxcy5maWx0ZXIoUShjcmVhdGVkX2J5PXVzZXIpIHwgUSh0cmFuc3BvcnRlcl9fdXNlcj11c2VyKSkuZGlzdGluY3QoKQo=").decode()
if 'getattr(self, "action", None) in ("retrieve", "accept"' in src:
    print("   already applied, skip"); sys.exit(0)
if old not in src:
    print("   ERROR anchor not found; aborting"); sys.exit(4)
src=src.replace(old,new,1)
try: ast.parse(src)
except SyntaxError as e:
    print("   ERROR would not parse: %s"%e); sys.exit(2)
open(p,"w",encoding="utf-8").write(src)
print("   OK logistics/api/views.py: detail actions can resolve open jobs")
PYEOF
rc=$?; set -e
if [ "$rc" -ne 0 ]; then echo ">> Failed (rc=$rc). Restoring."; cp -a "$BK/logistics/api/views.py" "$TGT"; exit "$rc"; fi
echo "DONE"; echo ">> Restart the server, then: python manage.py test escrow logistics --keepdb"
echo ">> Rollback: cp -a $BK/logistics/api/views.py $TGT"
