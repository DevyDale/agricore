#!/usr/bin/env bash
# Payout-account validation: check a seller's MoMo/bank details at save time so
# payouts do not silently fail later. Serializer only: no migration. Restart after.
set -uo pipefail
if [ ! -f escrow/api/serializers.py ] || [ ! -f manage.py ]; then
  echo "X Run from the Django project root."; exit 1
fi
BK="payout_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"; cp -a escrow/api/serializers.py "$BK/serializers.py"
echo ">> Backup: $BK/serializers.py"
cat > .payout.py << 'POW_EOF'
import sys, ast
SP='escrow/api/serializers.py'; s=open(SP,encoding='utf-8').read()
if 'def validate(self, attrs)' not in s:
    OLD='''class PayoutAccountSerializer(serializers.ModelSerializer):
    class Meta:'''
    NEW='''class PayoutAccountSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        """Validate a seller payout destination at save time so payouts do not
        silently fail later. Normalizes Ugandan mobile numbers and infers the
        network; bank payouts must carry a bank code."""
        inst = getattr(self, "instance", None)

        def cur(key, default=""):
            if key in attrs:
                return attrs.get(key)
            return getattr(inst, key, default) if inst is not None else default

        method = (cur("method", "momo") or "momo").lower()
        name = (cur("account_name", "") or "").strip()
        if not name:
            raise serializers.ValidationError({"account_name": "Account holder name is required."})
        number = (cur("account_number", "") or "").strip()

        if method == "momo":
            from utils.sms import normalize_ug
            norm = normalize_ug(number)
            digits = norm[1:] if norm.startswith("+") else norm
            if not (norm.startswith("+256") and len(digits) == 12 and digits[3] == "7"):
                raise serializers.ValidationError(
                    {"account_number": "Enter a valid Ugandan mobile money number, e.g. 0772123456."}
                )
            attrs["account_number"] = norm
            if not (cur("account_bank", "") or "").strip():
                attrs["account_bank"] = "MPS"
            if not (cur("network", "") or "").strip():
                pref = digits[3:5]
                if pref in {"77", "78", "76"}:
                    attrs["network"] = "MTN"
                elif pref in {"70", "75", "74"}:
                    attrs["network"] = "AIRTEL"
        else:
            if not number:
                raise serializers.ValidationError({"account_number": "Bank account number is required."})
            if not (cur("account_bank", "") or "").strip():
                raise serializers.ValidationError({"account_bank": "Bank code is required for bank payouts."})
        return attrs

    class Meta:'''
    if OLD not in s: print('   X PayoutAccountSerializer anchor not found'); sys.exit(1)
    s=s.replace(OLD,NEW,1)
    try: ast.parse(s)
    except SyntaxError as e: print('   X invalid result:',e); sys.exit(1)
    open(SP,'w',encoding='utf-8').write(s)
    print('   OK serializers.py: payout-account validation added')
else:
    print('   - serializers.py already has payout validation')
print('DONE')
POW_EOF
python3 .payout.py; RC=$?
rm -f .payout.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/serializers.py escrow/api/serializers.py"; exit 1; fi
echo ""
echo ">> Applied. Restart the server. No migration needed."
echo "   Sellers now get an instant error when saving a bad MoMo number or"
echo "   leaving the account name blank, instead of a stuck payout later."
echo ">> Rollback: cp -a $BK/serializers.py escrow/api/serializers.py"
