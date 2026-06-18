#!/usr/bin/env bash
# Seller contact on accept: the assigned rider sees the seller's name + phone
# (hidden from open-job browsers). Serializer + rider page. No migration.
set -uo pipefail
if [ ! -f logistics/api/serializers.py ] || [ ! -f templates/transporter.html ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="sellercontact_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a logistics/api/serializers.py "$BK/serializers.py"
cp -a templates/transporter.html "$BK/transporter.html"
echo ">> Backup: $BK/"
cat > .sc.py << 'SCW_EOF'
import sys, ast
# 1) logistics serializer: expose seller_name/seller_phone, gated to seller + assigned rider
SP='logistics/api/serializers.py'; s=open(SP,encoding='utf-8').read()
if 'def get_seller_name' not in s:
    A_OLD='''class DeliveryJobSerializer(serializers.ModelSerializer):
    class Meta:'''
    A_NEW='''class DeliveryJobSerializer(serializers.ModelSerializer):
    seller_name = serializers.SerializerMethodField()
    seller_phone = serializers.SerializerMethodField()

    def get_seller_name(self, obj):
        store = getattr(obj.order, "store", None)
        if not store:
            return ""
        return getattr(store, "owner_name", "") or getattr(store, "name", "") or ""

    def get_seller_phone(self, obj):
        store = getattr(obj.order, "store", None)
        return (getattr(store, "owner_phone", "") or "") if store else ""

    class Meta:'''
    if A_OLD not in s: print('   X DeliveryJobSerializer class anchor not found'); sys.exit(1)
    s=s.replace(A_OLD,A_NEW,1)
    B_OLD='''        if not (viewer is not None and getattr(instance, "created_by_id", None) == getattr(viewer, "id", None)):
            data.pop("pickup_code", None)
        return data'''
    B_NEW='''        _vid = getattr(viewer, "id", None)
        _is_creator = getattr(instance, "created_by_id", None) == _vid
        _is_rider = bool(getattr(instance, "transporter_id", None) and instance.transporter.user_id == _vid)
        if not _is_creator:
            data.pop("pickup_code", None)
        # Seller contact is shared only with the seller and the assigned rider.
        if not (_is_creator or _is_rider):
            data.pop("seller_name", None)
            data.pop("seller_phone", None)
        return data'''
    if B_OLD not in s: print('   X to_representation anchor not found'); sys.exit(1)
    s=s.replace(B_OLD,B_NEW,1)
    try: ast.parse(s)
    except SyntaxError as e: print('   X serializers invalid:',e); sys.exit(1)
    open(SP,'w',encoding='utf-8').write(s)
    print('   OK logistics serializer: seller_name/seller_phone (gated)')
else:
    print('   - serializer already exposes seller contact')

# 2) transporter.html: show seller contact on the rider's job card
HP='templates/transporter.html'; h=open(HP,encoding='utf-8').read()
if 'seller_phone' not in h:
    C_OLD="""      + (j.drop_location ? '<p class="text-xs text-gray-500"><i class="fas fa-flag-checkered"></i> to ' + esc(j.drop_location) + '</p>' : '')
      + '</div>'"""
    C_NEW="""      + (j.drop_location ? '<p class="text-xs text-gray-500"><i class="fas fa-flag-checkered"></i> to ' + esc(j.drop_location) + '</p>' : '')
      + ((j.seller_phone || j.seller_name) ? '<p class="text-xs text-gray-700 mt-1"><i class="fas fa-user-tie text-emerald-600"></i> Seller: ' + esc(j.seller_name || '\\u2014') + (j.seller_phone ? (' \\u00b7 <a href="tel:' + esc(j.seller_phone) + '" class="text-emerald-700 underline">' + esc(j.seller_phone) + '</a>') : '') + '</p>' : '')
      + '</div>'"""
    if C_OLD not in h: print('   X transporter jobCard anchor not found'); sys.exit(1)
    open(HP,'w',encoding='utf-8').write(h.replace(C_OLD,C_NEW,1))
    print('   OK transporter.html: seller contact on job card')
else:
    print('   - transporter.html already shows seller contact')
print('DONE')
SCW_EOF
python3 .sc.py; RC=$?
rm -f .sc.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/serializers.py" logistics/api/serializers.py
  cp -a "$BK/transporter.html" templates/transporter.html
  exit 1
fi
echo ""
echo ">> Applied. Restart the server; hard-refresh transporter.html."
echo ">> Rollback: cp -a $BK/serializers.py logistics/api/serializers.py && cp -a $BK/transporter.html templates/transporter.html"
