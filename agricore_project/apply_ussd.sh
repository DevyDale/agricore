#!/usr/bin/env bash
# Phase 3b: USSD for app-less riders (ready to connect). Shared pickup/deliver
# transition helpers (link + USSD use one implementation each), a stateless
# Africa's Talking callback at /api/ussd/, and the menu logic. No migration.
# After applying: in the Africa's Talking dashboard, point your USSD shortcode's
# callback URL at https://<your-host>/api/ussd/ to go live.
set -uo pipefail
if [ ! -f manage.py ]; then echo "X Run from the Django project root (where manage.py is)."; exit 1; fi

UP=""
for c in urls.py agricore_project/urls.py agricore_project/agricore_project/urls.py; do
  if [ -f "$c" ] && grep -q "RiderLinkDeliverView" "$c"; then UP="$c"; break; fi
done
if [ -z "$UP" ]; then
  for c in urls.py agricore_project/urls.py agricore_project/agricore_project/urls.py; do
    if [ -f "$c" ]; then UP="$c"; break; fi
  done
fi
if [ -z "$UP" ]; then echo "X Could not locate urls.py."; exit 1; fi

BK="ussd_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a logistics/api/views.py "$BK/views.py"
cp -a "$UP" "$BK/urls.py"
echo ">> Backup: $BK/  (urls.py = $UP)"

cat > .ussd.py << 'USSDW_EOF'
import sys, ast

def parse_or_die(p):
    try: ast.parse(open(p,encoding='utf-8').read())
    except SyntaxError as e:
        print('   X %s invalid: %s'%(p,e)); sys.exit(1)

# ===================== logistics/api/views.py =====================
VP='logistics/api/views.py'; v=open(VP,encoding='utf-8').read()
if 'def _do_pickup' not in v:
    # (a) imports
    I_OLD='from rest_framework.views import APIView\n'
    I_NEW='from rest_framework.views import APIView\nfrom django.http import HttpResponse\nfrom django.views.decorators.csrf import csrf_exempt\n'
    if I_OLD not in v: print('   X import anchor not found'); sys.exit(1)
    v=v.replace(I_OLD,I_NEW,1)

    # (b) shared transition helpers after _job_for_token
    A_OLD='''    )


class RiderLinkView(APIView):'''
    A_NEW='''    )


def _do_pickup(job, code):
    """Shared pickup transition (link endpoint + USSD). Validates the seller pickup
    code, marks the job picked up, and fires the buyer's delivery code. (ok, detail)."""
    if job.status != "accepted":
        return False, "Cannot pick up from status: %s." % job.status
    code = str(code or "").strip()
    if not job.pickup_code or code != job.pickup_code:
        return False, "Incorrect pickup code. Ask the seller for the code on their order."
    job.status = "picked_up"
    job.picked_up_at = timezone.now()
    job.save(update_fields=["status", "picked_up_at", "updated_at"])
    escrow = job.escrow
    if escrow is None:
        try:
            escrow = job.order.escrow
        except Exception:
            escrow = None
    try:
        if escrow is not None and escrow.status == "held":
            from escrow.api.views import issue_delivery_otp
            issue_delivery_otp(escrow)
    except Exception:
        pass
    return True, "Picked up. The buyer has been sent their delivery code."


def _do_deliver(job, otp):
    """Shared delivery transition (link endpoint + USSD). Validates the buyer's
    delivery code, confirms delivery, and starts the dispute window. (ok, detail)."""
    from datetime import timedelta
    if job.status != "picked_up":
        return False, "Cannot confirm delivery from status: %s." % job.status
    escrow = job.escrow
    if escrow is None:
        try:
            escrow = job.order.escrow
        except Exception:
            escrow = None
    if escrow is None:
        return False, "No escrow found for this delivery."
    if escrow.status != "held":
        return False, "Cannot confirm delivery from escrow status: %s." % escrow.status
    if not escrow.delivery_otp:
        return False, "No delivery code has been issued yet."
    otp = str(otp or "").strip()
    if otp != escrow.delivery_otp:
        return False, "Incorrect delivery code."
    from escrow.api.views import _dispute_window_hours_for
    hours = _dispute_window_hours_for(escrow.order)
    escrow.delivered_confirmed_at = timezone.now()
    escrow.dispute_deadline = timezone.now() + timedelta(hours=hours)
    escrow.save()
    order = escrow.order
    order.status = "delivered"
    order.save()
    job.status = "delivered"
    job.delivered_at = timezone.now()
    job.save(update_fields=["status", "delivered_at", "updated_at"])
    return True, "Delivery confirmed. Thank you!"


class RiderLinkView(APIView):'''
    if A_OLD not in v: print('   X _job_for_token/RiderLinkView boundary anchor not found'); sys.exit(1)
    v=v.replace(A_OLD,A_NEW,1)

    # (c) refactor RiderLinkPickupView.post to delegate
    P_OLD='''        if job.status != "accepted":
            return Response({"detail": f"Cannot pick up from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        supplied = str(request.data.get("pickup_code", "")).strip()
        if not job.pickup_code or supplied != job.pickup_code:
            return Response({"detail": "Incorrect pickup code. Ask the seller for the code on their order."}, status=status.HTTP_400_BAD_REQUEST)
        job.status = "picked_up"
        job.picked_up_at = timezone.now()
        job.save(update_fields=["status", "picked_up_at", "updated_at"])
        escrow = job.escrow
        if escrow is None:
            try:
                escrow = job.order.escrow
            except Exception:
                escrow = None
        sms_sent = False
        try:
            if escrow is not None and escrow.status == "held":
                from escrow.api.views import issue_delivery_otp
                sms_sent = issue_delivery_otp(escrow)
        except Exception:
            sms_sent = False
        return Response({"detail": "Picked up. The buyer has been sent their delivery code.", "sms_sent": sms_sent, "status": job.status})'''
    P_NEW='''        ok, detail = _do_pickup(job, request.data.get("pickup_code", ""))
        return Response({"detail": detail, "status": job.status}, status=(status.HTTP_200_OK if ok else status.HTTP_400_BAD_REQUEST))'''
    if P_OLD not in v: print('   X RiderLinkPickupView body anchor not found'); sys.exit(1)
    v=v.replace(P_OLD,P_NEW,1)

    # (d) refactor RiderLinkDeliverView.post to delegate
    D_OLD='''    def post(self, request, token=None):
        from datetime import timedelta
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        if job.status != "picked_up":
            return Response({"detail": f"Cannot confirm delivery from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        escrow = job.escrow
        if escrow is None:
            try:
                escrow = job.order.escrow
            except Exception:
                escrow = None
        if escrow is None:
            return Response({"detail": "No escrow found for this delivery."}, status=status.HTTP_400_BAD_REQUEST)
        if escrow.status != "held":
            return Response({"detail": f"Cannot confirm delivery from escrow status: {escrow.status}."}, status=status.HTTP_400_BAD_REQUEST)
        if not escrow.delivery_otp:
            return Response({"detail": "No delivery code has been issued yet."}, status=status.HTTP_400_BAD_REQUEST)
        supplied = str(request.data.get("otp", "")).strip()
        if supplied != escrow.delivery_otp:
            return Response({"detail": "Incorrect delivery code."}, status=status.HTTP_400_BAD_REQUEST)
        from escrow.api.views import _dispute_window_hours_for
        hours = _dispute_window_hours_for(escrow.order)
        escrow.delivered_confirmed_at = timezone.now()
        escrow.dispute_deadline = timezone.now() + timedelta(hours=hours)
        escrow.save()
        order = escrow.order
        order.status = "delivered"
        order.save()
        job.status = "delivered"
        job.delivered_at = timezone.now()
        job.save(update_fields=["status", "delivered_at", "updated_at"])
        return Response({"detail": "Delivery confirmed. Thank you!", "status": job.status})'''
    D_NEW='''    def post(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        ok, detail = _do_deliver(job, request.data.get("otp", ""))
        return Response({"detail": detail, "status": job.status}, status=(status.HTTP_200_OK if ok else status.HTTP_400_BAD_REQUEST))'''
    if D_OLD not in v: print('   X RiderLinkDeliverView body anchor not found'); sys.exit(1)
    v=v.replace(D_OLD,D_NEW,1)

    # (e) append USSD: pure menu logic + Django callback
    if not v.endswith('\n'): v+='\n'
    v=v+'''

def _ussd_render(text, jobs, do_pickup, do_deliver):
    """Pure USSD menu logic (no DB/IO) so it is testable against simulated Africa's
    Talking input chains. `jobs` are the rider's active jobs; do_pickup/do_deliver are
    the shared transition helpers. Returns a CON/END response string."""
    parts = text.split("*") if text else []

    def prompt_for(job):
        if job.status == "accepted":
            return "CON Order #%s to %s.\\nEnter the pickup code from the seller:" % (job.order_id, job.drop_location or "destination")
        return "CON Order #%s.\\nEnter the buyer's delivery code:" % job.order_id

    def process(job, code):
        if job.status == "accepted":
            _ok, detail = do_pickup(job, code)
        elif job.status == "picked_up":
            _ok, detail = do_deliver(job, code)
        else:
            detail = "This delivery is closed."
        return "END " + detail

    if not jobs:
        return "END You have no active Agricore deliveries."
    if len(jobs) == 1:
        job = jobs[0]
        if not parts:
            return prompt_for(job)
        return process(job, parts[-1])
    if not parts:
        lines = ["CON Your deliveries:"]
        for i, j in enumerate(jobs, 1):
            lines.append("%d. Order #%s (%s)" % (i, j.order_id, "pickup" if j.status == "accepted" else "deliver"))
        return "\\n".join(lines)
    try:
        job = jobs[int(parts[0]) - 1]
    except (ValueError, IndexError):
        return "END Invalid selection."
    if len(parts) == 1:
        return prompt_for(job)
    return process(job, parts[1])


@csrf_exempt
def ussd_callback(request):
    """Africa's Talking USSD callback. In the AT dashboard, point your shortcode's
    callback URL at https://<host>/api/ussd/ . Stateless: AT sends the full input
    chain in POST 'text' (parts separated by '*'). Responds CON (continue)/END (final)."""
    from utils.sms import normalize_ug
    if request.method != "POST":
        return HttpResponse("END Invalid request.", content_type="text/plain")
    phone = normalize_ug(request.POST.get("phoneNumber", "") or "")
    text = (request.POST.get("text", "") or "").strip()
    jobs = list(
        DeliveryJob.objects
        .select_related("order", "order__store", "escrow")
        .filter(access_phone=phone, status__in=["accepted", "picked_up"])
        .order_by("created_at")
    )
    body = _ussd_render(text, jobs, _do_pickup, _do_deliver)
    return HttpResponse(body, content_type="text/plain")
'''
    open(VP,'w',encoding='utf-8').write(v); parse_or_die(VP)
    print('   OK logistics/api/views.py: shared transition helpers + USSD callback')
else:
    print('   - logistics/api/views.py already has USSD')

# ===================== urls.py =====================
import os
UP='urls.py'
if not os.path.exists(UP):
    for cand in ['agricore_project/urls.py','agricore_project/agricore_project/urls.py']:
        if os.path.exists(cand): UP=cand; break
u=open(UP,encoding='utf-8').read()
if 'api/ussd/' not in u:
    IMP_OLD=', RiderLinkDeliverView'
    IMP_NEW=', RiderLinkDeliverView, ussd_callback'
    if IMP_OLD not in u: print('   X urls import anchor not found'); sys.exit(1)
    u=u.replace(IMP_OLD,IMP_NEW,1)
    P_OLD="    path('api/rider-link/<str:token>/deliver/', RiderLinkDeliverView.as_view()),"
    P_NEW=P_OLD+"\n    path('api/ussd/', ussd_callback),"
    if P_OLD not in u: print('   X urls deliver-path anchor not found'); sys.exit(1)
    u=u.replace(P_OLD,P_NEW,1)
    open(UP,'w',encoding='utf-8').write(u); parse_or_die(UP)
    print('   OK %s: /api/ussd/ route + import' % UP)
else:
    print('   - urls.py already has /api/ussd/')

print('DONE')
USSDW_EOF
python3 .ussd.py; RC=$?
rm -f .ussd.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/views.py" logistics/api/views.py
  cp -a "$BK/urls.py" "$UP"
  exit 1
fi
echo ""
echo ">> Applied. Restart the server."
echo ">> To go live: register a USSD shortcode on Africa's Talking and set its callback URL to"
echo "     https://<your-host>/api/ussd/"
echo "   Riders assigned by phone (via Send-SMS-link) can then dial the shortcode instead of opening the link."
echo ">> Rollback: cp -a $BK/views.py logistics/api/views.py && cp -a $BK/urls.py $UP"
