#!/usr/bin/env bash
# Dale AI -> reads REAL product ratings + recent review comments from the DB,
# so it can recommend products based on ratings AND reviews. Edits ai/api/views.py.
set -uo pipefail
if [ ! -f ai/api/views.py ]; then echo "X Run from the Django project root (the folder with manage.py / the ai app)."; exit 1; fi
BK="dalerev_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/ai/api"; cp ai/api/views.py "$BK/ai/api/views.py"
echo ">> Backup: $BK/ai/api/views.py"
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  git checkout -b feature/dale-reviews 2>/dev/null || echo "   (branch feature/dale-reviews exists or skipped; continuing)"
fi
cat > .dlrev.py << 'DLREV_PY_EOF'
import sys, ast
PATH='ai/api/views.py'
s=open(PATH,encoding='utf-8').read()
if 'Dale marketplace review-awareness' in s:
    print('   - Dale review-awareness already present'); sys.exit(0)

ANCHOR = "        messages.append({'role': 'user', 'content': prompt})"
if ANCHOR not in s:
    print('   X user-prompt anchor not found -> untouched'); sys.exit(1)

BLOCK = '''        # ---- Dale marketplace review-awareness (reads real ratings + recent reviews) ----
        try:
            _blob = (str(page) + ' ' + str(context_type) + ' ' + str(extras)).lower()
        except Exception:
            _blob = ''
        if 'market' in _blob or 'product' in _blob:
            try:
                from marketplace.models import Product, ProductReview
                from django.db.models import Avg, Count
                _prods = (Product.objects
                          .select_related('store')
                          .annotate(dale_avg=Avg('product_reviews__rating'),
                                    dale_cnt=Count('product_reviews'))
                          .order_by('-dale_avg', '-dale_cnt')[:25])
                _ids = [p.id for p in _prods]
                _rev_map = {}
                for _r in (ProductReview.objects.filter(product_id__in=_ids)
                           .order_by('-created_at')
                           .values('product_id', 'rating', 'comment')):
                    _lst = _rev_map.setdefault(_r['product_id'], [])
                    if len(_lst) < 2:
                        _c = (_r['comment'] or '').replace('\\n', ' ').strip()
                        if len(_c) > 140:
                            _c = _c[:140] + '...'
                        _lst.append((_r['rating'], _c))
                _lines = []
                for p in _prods:
                    _avg = round(p.dale_avg, 1) if p.dale_avg is not None else None
                    _store = getattr(p, 'store', None)
                    _row = ('- ' + str(getattr(p, 'title', '') or '')
                            + ' | $' + str(getattr(p, 'price', '')) + ' per ' + str(getattr(p, 'unit', 'unit') or 'unit')
                            + ' | ' + str(getattr(p, 'category', '') or '')
                            + ' | store: ' + str(getattr(_store, 'name', '') or '')
                            + ' | rating: ' + (str(_avg) if _avg is not None else 'none')
                            + ' (' + str(p.dale_cnt) + ' reviews) | stock: ' + str(getattr(p, 'stock_quantity', 0)))
                    _rv = _rev_map.get(p.id) or []
                    if _rv:
                        _row += ' | recent reviews: ' + ' ; '.join(
                            ((str(_rt) + '/5 "' + _cc + '"') if _cc else (str(_rt) + '/5')) for _rt, _cc in _rv)
                    _lines.append(_row)
                if _lines:
                    _catalog = ('Live marketplace data with real ratings and recent customer reviews. '
                                'Use this to recommend products and justify each pick by citing the rating and what reviewers actually said. '
                                'Best-rated first:\\n' + '\\n'.join(_lines))
                    messages.append({'role': 'system', 'content': _catalog[:5000]})
            except Exception:
                pass

'''

s = s.replace(ANCHOR, BLOCK + ANCHOR, 1)
try:
    ast.parse(s)
except SyntaxError as e:
    print('   X edit would break Python syntax, aborting:', e); sys.exit(1)
open(PATH,'w',encoding='utf-8').write(s)
print('   OK Dale now reads live ratings + recent reviews for recommendations')
DLREV_PY_EOF
python3 .dlrev.py; RC=$?
rm -f .dlrev.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/ai/api/views.py ai/api/views.py"; exit 1; fi
echo ">> Now run:  python manage.py check   then restart your server."
echo ">> Rollback: cp -a $BK/ai/api/views.py ai/api/views.py"
