#!/usr/bin/env bash
# Proof of condition (backend): photo + recorded quantity on dispatch (seller)
# and on dispute (buyer), stored on the escrow as evidence. Additive. After
# running: makemigrations + migrate.
set -uo pipefail
if [ ! -f escrow/models.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="proof_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"; cp -a escrow "$BK/escrow"
echo ">> Backup: $BK/escrow"
cat > .proof.py << 'PROOFW_EOF'
import sys, ast
def parse_or_die(p):
    try: ast.parse(open(p,encoding='utf-8').read())
    except SyntaxError as e:
        print('   X resulting %s invalid: %s'%(p,e)); sys.exit(1)

# 1) models.py: 5 proof fields after dispute_reason
MP='escrow/models.py'; m=open(MP,encoding='utf-8').read()
if 'dispatch_photo' not in m:
    OLD='''    dispute_reason = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)'''
    NEW='''    dispute_reason = models.TextField(blank=True, default="")
    # ---- Proof of condition: photos + recorded quantity at dispatch and dispute ----
    dispatch_quantity = models.CharField(max_length=120, blank=True, default="")
    dispatch_note = models.TextField(blank=True, default="")
    dispatch_photo = models.ImageField(upload_to="trade_proof/", blank=True, null=True)
    dispute_quantity = models.CharField(max_length=120, blank=True, default="")
    dispute_photo = models.ImageField(upload_to="trade_proof/", blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)'''
    if OLD not in m: print('   X models anchor not found'); sys.exit(1)
    open(MP,'w',encoding='utf-8').write(m.replace(OLD,NEW,1)); parse_or_die(MP)
    print('   OK models.py: 5 proof fields added')
else: print('   - models.py already has proof fields')

# 2) serializers.py: mark proof fields read-only
SP='escrow/api/serializers.py'; s=open(SP,encoding='utf-8').read()
if 'dispatch_photo' not in s:
    OLD='''            "dispute_reason": {"read_only": True},
        }'''
    NEW='''            "dispute_reason": {"read_only": True},
            "dispatch_quantity": {"read_only": True},
            "dispatch_note": {"read_only": True},
            "dispatch_photo": {"read_only": True},
            "dispute_quantity": {"read_only": True},
            "dispute_photo": {"read_only": True},
        }'''
    if OLD not in s: print('   X serializers anchor not found'); sys.exit(1)
    open(SP,'w',encoding='utf-8').write(s.replace(OLD,NEW,1)); parse_or_die(SP)
    print('   OK serializers.py: proof fields read-only')
else: print('   - serializers.py already patched')

# 3) views.py: capture proof in issue_otp (dispatch) and dispute (buyer)
VP='escrow/api/views.py'; v=open(VP,encoding='utf-8').read()
if 'dispatch_quantity' not in v:
    D_OLD='''        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
        escrow.otp_issued_at = timezone.now()
        escrow.save()'''
    D_NEW='''        escrow.delivery_otp = f"{secrets.randbelow(900000) + 100000}"
        escrow.otp_issued_at = timezone.now()
        escrow.dispatch_quantity = str(request.data.get("dispatch_quantity", "") or "").strip()[:120]
        escrow.dispatch_note = str(request.data.get("dispatch_note", "") or "").strip()[:2000]
        _photo = request.data.get("dispatch_photo")
        if _photo is not None and hasattr(_photo, "read"):
            escrow.dispatch_photo = _photo
        escrow.save()'''
    if D_OLD not in v: print('   X issue_otp anchor not found'); sys.exit(1)
    v=v.replace(D_OLD,D_NEW,1)
    P_OLD='''        escrow.status = "disputed"
        escrow.dispute_reason = str(request.data.get("reason", "")).strip()[:2000]
        escrow.save()
        return Response(self.get_serializer(escrow).data)'''
    P_NEW='''        escrow.status = "disputed"
        escrow.dispute_reason = str(request.data.get("reason", "")).strip()[:2000]
        escrow.dispute_quantity = str(request.data.get("dispute_quantity", "") or "").strip()[:120]
        _dphoto = request.data.get("dispute_photo")
        if _dphoto is not None and hasattr(_dphoto, "read"):
            escrow.dispute_photo = _dphoto
        escrow.save()
        return Response(self.get_serializer(escrow).data)'''
    if P_OLD not in v: print('   X dispute anchor not found'); sys.exit(1)
    v=v.replace(P_OLD,P_NEW,1)
    open(VP,'w',encoding='utf-8').write(v); parse_or_die(VP)
    print('   OK views.py: dispatch + dispute now capture proof')
else: print('   - views.py already patched')
print('DONE')
PROOFW_EOF
python3 .proof.py; RC=$?
rm -f .proof.py
if [ $RC -ne 0 ]; then echo "X failed; restore: rm -rf escrow && cp -a $BK/escrow escrow"; exit 1; fi
echo ""
echo ">> Code applied. Create + apply the migration:"
echo "     python manage.py makemigrations escrow && python manage.py migrate && python manage.py check"
echo "   then restart the server. (Photos save under MEDIA_ROOT/trade_proof/.)"
echo ">> Rollback: rm -rf escrow && cp -a $BK/escrow escrow"
