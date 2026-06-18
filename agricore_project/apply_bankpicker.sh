#!/usr/bin/env bash
set -euo pipefail

VIEWS="escrow/api/views.py"
DS="templates/digital_store.html"
TR="templates/transporter.html"

BR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [ -n "$BR" ] && [ "$BR" != "dev" ]; then
  echo ">> Refusing: current branch is '$BR', not 'dev'."; exit 1
fi
for f in "$VIEWS" "$DS" "$TR"; do
  [ -f "$f" ] || { echo ">> Not found: $f (run from the Django root)"; exit 1; }
done

TS="$(date +%Y%m%d-%H%M%S)"
BK="bankpicker_backup_${TS}"
mkdir -p "$BK/escrow/api" "$BK/templates"
cp -a "$VIEWS" "$BK/escrow/api/views.py"
cp -a "$DS" "$BK/templates/digital_store.html"
cp -a "$TR" "$BK/templates/transporter.html"
echo ">> Backup: $BK/"

set +e
python3 - "$VIEWS" "$DS" "$TR" <<'PYEOF'
import sys, ast, base64
VIEWS, DS, TR = sys.argv[1], sys.argv[2], sys.argv[3]

def d(s): return base64.b64decode(s).decode("utf-8")

edits = {
  "views": [
    ("def banks(self, request)", d("ICAgIGRlZiBnZXRfcXVlcnlzZXQoc2VsZik6CiAgICAgICAgcmV0dXJuIFBheW91dEFjY291bnQub2JqZWN0cy5maWx0ZXIodXNlcj1zZWxmLnJlcXVlc3QudXNlcikKCiAgICBkZWYgcGVyZm9ybV9jcmVhdGUoc2VsZiwgc2VyaWFsaXplcik6Cg=="), d("ICAgIGRlZiBnZXRfcXVlcnlzZXQoc2VsZik6CiAgICAgICAgcmV0dXJuIFBheW91dEFjY291bnQub2JqZWN0cy5maWx0ZXIodXNlcj1zZWxmLnJlcXVlc3QudXNlcikKCiAgICBAYWN0aW9uKGRldGFpbD1GYWxzZSwgbWV0aG9kcz1bImdldCJdKQogICAgZGVmIGJhbmtzKHNlbGYsIHJlcXVlc3QpOgogICAgICAgICIiIkZsdXR0ZXJ3YXZlLXN1cHBvcnRlZCBiYW5rcyBmb3IgdGhlIHBheW91dCBiYW5rIHBpY2tlci4iIiIKICAgICAgICBjb3VudHJ5ID0gcmVxdWVzdC5xdWVyeV9wYXJhbXMuZ2V0KCJjb3VudHJ5IiwgIlVHIikKICAgICAgICB0cnk6CiAgICAgICAgICAgIHJldHVybiBSZXNwb25zZSh7ImJhbmtzIjogZmx1dHRlcndhdmUubGlzdF9iYW5rcyhjb3VudHJ5KX0pCiAgICAgICAgZXhjZXB0IGZsdXR0ZXJ3YXZlLkZsdXR0ZXJ3YXZlRXJyb3IgYXMgZToKICAgICAgICAgICAgcmV0dXJuIFJlc3BvbnNlKHsiYmFua3MiOiBbXSwgImRldGFpbCI6IHN0cihlKX0pCgogICAgZGVmIHBlcmZvcm1fY3JlYXRlKHNlbGYsIHNlcmlhbGl6ZXIpOgo=")),
  ],
  "ds": [
    ('<select id="po-bank-code"', d("ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxpbnB1dCB0eXBlPSJ0ZXh0IiBpZD0icG8tYmFuay1jb2RlIiBjbGFzcz0idy1mdWxsIGJvcmRlciBib3JkZXItZ3JheS0yMDAgcm91bmRlZC14bCBweC00IHB5LTIuNSBmb2N1czpvdXRsaW5lLW5vbmUgZm9jdXM6cmluZy0yIGZvY3VzOnJpbmctZW1lcmFsZC01MDAiIHBsYWNlaG9sZGVyPSJlLmcuIDA0NCI+Cg=="), d("ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxzZWxlY3QgaWQ9InBvLWJhbmstY29kZSIgY2xhc3M9InctZnVsbCBib3JkZXIgYm9yZGVyLWdyYXktMjAwIHJvdW5kZWQteGwgcHgtNCBweS0yLjUgZm9jdXM6b3V0bGluZS1ub25lIGZvY3VzOnJpbmctMiBmb2N1czpyaW5nLWVtZXJhbGQtNTAwIj48b3B0aW9uIHZhbHVlPSIiPlNlbGVjdCB5b3VyIGJhbmsmaGVsbGlwOzwvb3B0aW9uPjwvc2VsZWN0Pgo=")),
    ("Pick the bank that holds your account.", d("ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0idGV4dC14cyB0ZXh0LWdyYXktNDAwIj5Vc2UgeW91ciBGbHV0dGVyd2F2ZSBiYW5rIGNvZGUgKGUuZy4gMDQ0ID0gQWNjZXNzIEJhbmspLjwvcD4K"), d("ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0idGV4dC14cyB0ZXh0LWdyYXktNDAwIj5QaWNrIHRoZSBiYW5rIHRoYXQgaG9sZHMgeW91ciBhY2NvdW50LjwvcD4K")),
    ("loadPayoutBanks", d("ICAgICAgICAgICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3dhbGxldC1yZWZyZXNoJyk/LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywgKCkgPT4geyBNS1QubG9hZGVkID0gZmFsc2U7IGxvYWRXYWxsZXQoKTsgfSk7CiAgICAgICAgICAgIHNldFBvTWV0aG9kKCdtb21vJyk7CiAgICAgICAgfQo="), d("ICAgICAgICAgICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3dhbGxldC1yZWZyZXNoJyk/LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywgKCkgPT4geyBNS1QubG9hZGVkID0gZmFsc2U7IGxvYWRXYWxsZXQoKTsgfSk7CiAgICAgICAgICAgIHNldFBvTWV0aG9kKCdtb21vJyk7CiAgICAgICAgICAgIGxvYWRQYXlvdXRCYW5rcygpOwogICAgICAgIH0KCiAgICAgICAgYXN5bmMgZnVuY3Rpb24gbG9hZFBheW91dEJhbmtzKCl7CiAgICAgICAgICAgIGNvbnN0IHNlbCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwby1iYW5rLWNvZGUnKTsgaWYgKCFzZWwpIHJldHVybjsKICAgICAgICAgICAgaWYgKHNlbC5kYXRhc2V0LmxvYWRlZCA9PT0gJzEnKSByZXR1cm47CiAgICAgICAgICAgIGNvbnN0IHRvVGV4dCA9ICgpID0+IHsgaWYgKHNlbC50YWdOYW1lID09PSAnSU5QVVQnKSByZXR1cm47IGNvbnN0IGkgPSBkb2N1bWVudC5jcmVhdGVFbGVtZW50KCdpbnB1dCcpOyBpLnR5cGUgPSAndGV4dCc7IGkuaWQgPSAncG8tYmFuay1jb2RlJzsgaS5jbGFzc05hbWUgPSBzZWwuY2xhc3NOYW1lOyBpLnBsYWNlaG9sZGVyID0gJ0JhbmsgY29kZSAoZS5nLiAwNDQpJzsgc2VsLnJlcGxhY2VXaXRoKGkpOyB9OwogICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgY29uc3QgciA9IGF3YWl0IHdhbGxldEFwaSgncGF5b3V0LWFjY291bnRzL2JhbmtzLycpOwogICAgICAgICAgICAgICAgaWYgKCFyLm9rKSB7IHRvVGV4dCgpOyByZXR1cm47IH0KICAgICAgICAgICAgICAgIGNvbnN0IGRhdGEgPSBhd2FpdCByLmpzb24oKTsKICAgICAgICAgICAgICAgIGNvbnN0IGJhbmtzID0gKGRhdGEgJiYgZGF0YS5iYW5rcykgfHwgW107CiAgICAgICAgICAgICAgICBpZiAoIWJhbmtzLmxlbmd0aCkgeyB0b1RleHQoKTsgcmV0dXJuOyB9CiAgICAgICAgICAgICAgICBjb25zdCB3YW50ID0gKHBheW91dEFjY291bnQgJiYgcGF5b3V0QWNjb3VudC5hY2NvdW50X2JhbmspIHx8IHNlbC52YWx1ZSB8fCAnJzsKICAgICAgICAgICAgICAgIHNlbC5pbm5lckhUTUwgPSAnPG9wdGlvbiB2YWx1ZT0iIj5TZWxlY3QgeW91ciBiYW5rXHUyMDI2PC9vcHRpb24+JwogICAgICAgICAgICAgICAgICAgICsgYmFua3MubWFwKGIgPT4gJzxvcHRpb24gdmFsdWU9IicgKyBlc2NhcGVIdG1sKGIuY29kZSkgKyAnIj4nICsgZXNjYXBlSHRtbChiLm5hbWUpICsgJzwvb3B0aW9uPicpLmpvaW4oJycpOwogICAgICAgICAgICAgICAgaWYgKHdhbnQgJiYgd2FudCAhPT0gJ01QUycpIHNlbC52YWx1ZSA9IHdhbnQ7CiAgICAgICAgICAgICAgICBzZWwuZGF0YXNldC5sb2FkZWQgPSAnMSc7CiAgICAgICAgICAgIH0gY2F0Y2ggKGUpIHsgdG9UZXh0KCk7IH0KICAgICAgICB9Cg==")),
  ],
  "tr": [
    ('<select id="po_bank"', d("ICAgICAgKyAnPGlucHV0IGlkPSJwb19iYW5rIiBjbGFzcz0iaW5wMiIgcGxhY2Vob2xkZXI9IkJhbmsgY29kZSAoYmFuayBvbmx5KSI+Jwo="), d("ICAgICAgKyAnPHNlbGVjdCBpZD0icG9fYmFuayIgY2xhc3M9ImlucDIiPjxvcHRpb24gdmFsdWU9IiI+QmFuayAoc2VsZWN0IGlmIHBheWluZyB0byBhIGJhbmspPC9vcHRpb24+PC9zZWxlY3Q+Jwo=")),
    ("payout-accounts/banks/", d("ICAgIGlmIChteVBheW91dCkgewogICAgICBpZiAobXlQYXlvdXQubWV0aG9kKSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbWV0aG9kJykudmFsdWUgPSBteVBheW91dC5tZXRob2Q7CiAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwb19udW0nKS52YWx1ZSA9IG15UGF5b3V0LmFjY291bnRfbnVtYmVyIHx8ICcnOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbmFtZScpLnZhbHVlID0gbXlQYXlvdXQuYWNjb3VudF9uYW1lIHx8ICcnOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbmV0JykudmFsdWUgPSBteVBheW91dC5uZXR3b3JrIHx8ICcnOwogICAgfQogIH0K"), d("ICAgIGlmIChteVBheW91dCkgewogICAgICBpZiAobXlQYXlvdXQubWV0aG9kKSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbWV0aG9kJykudmFsdWUgPSBteVBheW91dC5tZXRob2Q7CiAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwb19udW0nKS52YWx1ZSA9IG15UGF5b3V0LmFjY291bnRfbnVtYmVyIHx8ICcnOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbmFtZScpLnZhbHVlID0gbXlQYXlvdXQuYWNjb3VudF9uYW1lIHx8ICcnOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9fbmV0JykudmFsdWUgPSBteVBheW91dC5uZXR3b3JrIHx8ICcnOwogICAgfQogICAgKGFzeW5jIGZ1bmN0aW9uICgpIHsKICAgICAgdmFyIHNlbCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwb19iYW5rJyk7IGlmICghc2VsKSByZXR1cm47CiAgICAgIHZhciB0b1RleHQgPSBmdW5jdGlvbiAoKSB7IHZhciBpID0gZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnaW5wdXQnKTsgaS5pZCA9ICdwb19iYW5rJzsgaS5jbGFzc05hbWUgPSBzZWwuY2xhc3NOYW1lOyBpLnBsYWNlaG9sZGVyID0gJ0JhbmsgY29kZSAoYmFuayBvbmx5KSc7IHNlbC5yZXBsYWNlV2l0aChpKTsgfTsKICAgICAgdHJ5IHsKICAgICAgICB2YXIgYmQgPSBhd2FpdCBhcGkoJy9wYXlvdXQtYWNjb3VudHMvYmFua3MvJyk7CiAgICAgICAgdmFyIGJhbmtzID0gKGJkICYmIGJkLmJhbmtzKSB8fCBbXTsKICAgICAgICBpZiAoIWJhbmtzLmxlbmd0aCkgeyB0b1RleHQoKTsgcmV0dXJuOyB9CiAgICAgICAgc2VsLmlubmVySFRNTCA9ICc8b3B0aW9uIHZhbHVlPSIiPkJhbmsgKHNlbGVjdCBpZiBwYXlpbmcgdG8gYSBiYW5rKTwvb3B0aW9uPicKICAgICAgICAgICsgYmFua3MubWFwKGZ1bmN0aW9uIChiKSB7IHJldHVybiAnPG9wdGlvbiB2YWx1ZT0iJyArIGVzYyhiLmNvZGUpICsgJyI+JyArIGVzYyhiLm5hbWUpICsgJzwvb3B0aW9uPic7IH0pLmpvaW4oJycpOwogICAgICAgIGlmIChteVBheW91dCAmJiBteVBheW91dC5hY2NvdW50X2JhbmsgJiYgbXlQYXlvdXQuYWNjb3VudF9iYW5rICE9PSAnTVBTJykgc2VsLnZhbHVlID0gbXlQYXlvdXQuYWNjb3VudF9iYW5rOwogICAgICB9IGNhdGNoIChlKSB7IHRvVGV4dCgpOyB9CiAgICB9KSgpOwogIH0K")),
  ],
}

def apply(path, group, label, is_python):
    src = open(path, encoding="utf-8").read()
    changed = False
    for marker, old, new in edits[group]:
        if marker in src:
            print("   %s: '%s' already present, skip" % (label, marker[:32]))
            continue
        if old not in src:
            print("   ERROR %s: anchor not found for marker '%s'; aborting" % (label, marker[:32]))
            sys.exit(5)
        src = src.replace(old, new, 1)
        changed = True
        print("   OK %s: applied (%s)" % (label, marker[:40]))
    if changed:
        if is_python:
            try:
                ast.parse(src)
            except SyntaxError as e:
                print("   ERROR %s would not parse: %s" % (label, e)); sys.exit(6)
        open(path, "w", encoding="utf-8").write(src)

apply(VIEWS, "views", "views.py", True)
apply(DS, "ds", "digital_store.html", False)
apply(TR, "tr", "transporter.html", False)
print("   all edits done")
PYEOF
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  echo ">> Patch failed (rc=$rc). Restoring backup."
  cp -a "$BK/escrow/api/views.py" "$VIEWS"
  cp -a "$BK/templates/digital_store.html" "$DS"
  cp -a "$BK/templates/transporter.html" "$TR"
  exit "$rc"
fi

echo "DONE"
echo
echo ">> Restart the server; hard-refresh digital_store.html and transporter.html."
echo ">> New endpoint: GET /api/payout-accounts/banks/  (used to fill the bank dropdowns)"
echo ">> Rollback: cp -a $BK/escrow/api/views.py $VIEWS && cp -a $BK/templates/digital_store.html $DS && cp -a $BK/templates/transporter.html $TR"
