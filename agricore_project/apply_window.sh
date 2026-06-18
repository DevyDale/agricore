#!/usr/bin/env bash
# Perishable/livestock-aware dispute window: 24h for fast-spoiling goods, 72h
# otherwise (configurable). Backend only: no migration. Restart afterwards.
set -uo pipefail
if [ ! -f escrow/api/views.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="window_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"; cp -a escrow/api/views.py "$BK/views.py"
echo ">> Backup: $BK/views.py"
cat > .window.py << 'WINW_EOF'
import sys, ast
VP='escrow/api/views.py'; v=open(VP,encoding='utf-8').read()
if '_dispute_window_hours_for' not in v:
    # 1) insert the category-aware window helper before initiate_seller_payout
    H_OLD='''def initiate_seller_payout(escrow):'''
    H_NEW='''def _dispute_window_hours_for(order):
    """Pick the dispute window by what is being sold. Perishables and livestock
    (which spoil or lose condition fast in Uganda) get a shorter window so the
    seller is not made to wait days on goods that will not last. Overridable via
    settings: ESCROW_DISPUTE_WINDOW_HOURS, ESCROW_PERISHABLE_WINDOW_HOURS,
    ESCROW_PERISHABLE_CATEGORIES."""
    from django.conf import settings as _s
    default_h = getattr(_s, "ESCROW_DISPUTE_WINDOW_HOURS", 72)
    persh_h = getattr(_s, "ESCROW_PERISHABLE_WINDOW_HOURS", 24)
    keywords = getattr(_s, "ESCROW_PERISHABLE_CATEGORIES", None)
    if keywords is None:
        keywords = ["veg", "fruit", "dairy", "milk", "egg", "poultry", "meat",
                    "fish", "livestock", "perishable", "tomato", "matoke",
                    "banana", "flower", "herb"]
    keywords = [str(k).lower() for k in keywords]
    try:
        for item in order.orderitem_set.all():
            cat = str(getattr(getattr(item, "product", None), "category", "") or "").lower()
            if any(k in cat for k in keywords):
                return persh_h
    except Exception:
        pass
    return default_h


def initiate_seller_payout(escrow):'''
    if H_OLD not in v: print('   X helper anchor not found'); sys.exit(1)
    v=v.replace(H_OLD,H_NEW,1)
    # 2) use it in confirm_delivery
    L_OLD='''        hours = getattr(settings, "ESCROW_DISPUTE_WINDOW_HOURS", 72)'''
    L_NEW='''        hours = _dispute_window_hours_for(escrow.order)'''
    if L_OLD not in v: print('   X confirm_delivery window line not found'); sys.exit(1)
    v=v.replace(L_OLD,L_NEW,1)
    try: ast.parse(v)
    except SyntaxError as e: print('   X invalid result:',e); sys.exit(1)
    open(VP,'w',encoding='utf-8').write(v)
    print('   OK views.py: dispute window now perishable/livestock-aware')
else:
    print('   - views.py already window-aware')
print('DONE')
WINW_EOF
python3 .window.py; RC=$?
rm -f .window.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/views.py escrow/api/views.py"; exit 1; fi
echo ""
echo ">> Applied. Restart the server. No migration needed."
echo ">> Tune in settings.py (optional):"
echo "       ESCROW_DISPUTE_WINDOW_HOURS = 72"
echo "       ESCROW_PERISHABLE_WINDOW_HOURS = 24"
echo "       ESCROW_PERISHABLE_CATEGORIES = [\"veg\", \"fruit\", \"dairy\", \"livestock\", ...]"
echo ">> Rollback: cp -a $BK/views.py escrow/api/views.py"
