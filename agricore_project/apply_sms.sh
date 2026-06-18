#!/usr/bin/env bash
# Verified Trade Chain v1 -- SMS delivery codes (Uganda). Adds utils/sms.py and
# makes issue_otp text the buyer's delivery code to any phone (Africa's Talking,
# with a console-log fallback so dev works with no gateway). Backend only:
# no migration. Restart the server afterwards.
set -uo pipefail
if [ ! -f escrow/api/views.py ] || [ ! -d utils ]; then
  echo "X Run from the Django project root (needs escrow/api/views.py and the utils/ package)."; exit 1
fi
BK="sms_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a escrow/api/views.py "$BK/views.py"
HADSMS=0; [ -f utils/sms.py ] && { HADSMS=1; cp -a utils/sms.py "$BK/sms.py"; }
echo ">> Backup: $BK/"
cat > .sms.py << 'SMSW_EOF'
import sys, os, ast

def parse_or_die(path):
    try:
        ast.parse(open(path, encoding='utf-8').read())
    except SyntaxError as e:
        print('   X resulting %s invalid: %s' % (path, e)); sys.exit(1)

SMS_SRC = r'''"""Lightweight SMS sender for Agricore (Uganda).

Sends the buyer's delivery code to any phone, so feature-phone buyers don't need
the app. Provider is chosen by Django settings; falls back to console logging in
dev so flows work with no gateway configured.

Production settings (add to settings.py or env):
    SMS_PROVIDER = "africastalking"      # default: "console" (logs only)
    AT_USERNAME  = "your_at_username"    # "sandbox" for testing
    AT_API_KEY   = "your_at_api_key"
    AT_SENDER_ID = "AGRICORE"            # optional approved sender ID/short code
"""
import logging

try:
    import requests
except Exception:  # requests not installed -> only the console backend works
    requests = None

logger = logging.getLogger(__name__)


class SMSError(Exception):
    pass


def _setting(name, default=""):
    try:
        from django.conf import settings
        return getattr(settings, name, default)
    except Exception:
        return default


def normalize_ug(raw):
    """Best-effort normalization of a Ugandan number to +2567XXXXXXXX."""
    s = "".join(ch for ch in str(raw or "") if ch.isdigit() or ch == "+")
    if not s:
        return ""
    if s.startswith("+"):
        return s
    if s.startswith("256"):
        return "+" + s
    if s.startswith("0"):
        return "+256" + s[1:]
    if s.startswith("7") and len(s) == 9:
        return "+256" + s
    return "+" + s


def send_sms(to, message):
    """Send one SMS. Returns True if handed off to a backend, False if skipped.
    Never raises for an unconfigured gateway -- it degrades to console logging."""
    number = normalize_ug(to)
    if not number:
        logger.warning("send_sms: missing/invalid phone; skipped")
        return False

    provider = str(_setting("SMS_PROVIDER", "console")).lower()
    if provider == "africastalking":
        try:
            return _send_africastalking(number, message)
        except SMSError as e:
            logger.error("send_sms: Africa's Talking failed: %s", e)
            logger.info("[SMS:fallback] to=%s msg=%s", number, message)
            return False

    logger.info("[SMS:console] to=%s msg=%s", number, message)
    return True


def _send_africastalking(number, message):
    username = _setting("AT_USERNAME", "sandbox")
    api_key = _setting("AT_API_KEY", "")
    sender = _setting("AT_SENDER_ID", "")
    if not api_key or requests is None:
        raise SMSError("Africa's Talking not configured (AT_API_KEY missing or requests unavailable)")

    base = "https://api.sandbox.africastalking.com" if username == "sandbox" else "https://api.africastalking.com"
    url = base + "/version1/messaging"
    data = {"username": username, "to": number, "message": message}
    if sender:
        data["from"] = sender
    headers = {"apiKey": api_key, "Accept": "application/json",
               "Content-Type": "application/x-www-form-urlencoded"}
    try:
        r = requests.post(url, data=data, headers=headers, timeout=20)
    except Exception as e:
        raise SMSError(str(e))
    if r.status_code not in (200, 201):
        raise SMSError("HTTP %s: %s" % (r.status_code, (r.text or "")[:200]))
    return True
'''

# 1) create utils/sms.py if missing
SP = 'utils/sms.py'
if not os.path.exists('utils'):
    print('   X utils/ package not found here -> run from project root'); sys.exit(1)
if not os.path.exists(SP):
    open(SP, 'w', encoding='utf-8').write(SMS_SRC)
    parse_or_die(SP)
    print('   OK utils/sms.py created')
else:
    print('   - utils/sms.py already exists (left as-is)')

# 2) wire issue_otp to SMS the buyer
VP = 'escrow/api/views.py'
v = open(VP, encoding='utf-8').read()
if 'from utils.sms import send_sms' not in v:
    OLD = '''        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
        escrow.otp_issued_at = timezone.now()
        escrow.save()
        return Response({"detail": "Dispatched. The buyer can now see their delivery code."})'''
    NEW = '''        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
        escrow.otp_issued_at = timezone.now()
        escrow.save()
        # Send the code to the buyer by SMS so a feature-phone buyer gets it without the app.
        sms_sent = False
        try:
            from utils.sms import send_sms
            phone = getattr(escrow.buyer, "phone", "") or ""
            if phone:
                msg = f"Agricore: delivery code for order #{escrow.order_id} is {escrow.delivery_otp}. Give it to the courier only when your goods arrive."
                sms_sent = bool(send_sms(phone, msg))
        except Exception:
            sms_sent = False
        return Response({"detail": "Dispatched. The buyer has been sent their delivery code.", "sms_sent": sms_sent})'''
    if OLD not in v:
        print('   X issue_otp anchor not found -> views.py untouched'); sys.exit(1)
    open(VP, 'w', encoding='utf-8').write(v.replace(OLD, NEW, 1))
    parse_or_die(VP)
    print('   OK escrow/api/views.py: issue_otp now SMSes the buyer')
else:
    print('   - escrow/api/views.py already wired to SMS')

print('DONE')
SMSW_EOF
python3 .sms.py; RC=$?
rm -f .sms.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/views.py" escrow/api/views.py
  if [ "$HADSMS" -eq 1 ]; then cp -a "$BK/sms.py" utils/sms.py; else rm -f utils/sms.py; fi
  exit 1
fi
echo ""
echo ">> Applied. Restart the server. No migration needed."
echo ">> Dev: with nothing configured, the code is LOGGED to the server console"
echo "   (and still shown in-app to the buyer). To send real SMS, add to settings.py:"
echo "       SMS_PROVIDER = \"africastalking\""
echo "       AT_USERNAME  = \"sandbox\"   # or your live username"
echo "       AT_API_KEY   = \"<your key>\""
echo "       AT_SENDER_ID = \"AGRICORE\"  # optional"
echo ">> Rollback: cp -a $BK/views.py escrow/api/views.py$([ "$HADSMS" -eq 1 ] && echo " && cp -a $BK/sms.py utils/sms.py" || echo " && rm -f utils/sms.py")"
