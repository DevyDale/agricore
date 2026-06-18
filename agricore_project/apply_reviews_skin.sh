#!/usr/bin/env bash
# Reviews / product-detail dialog -> premium restyle (scoped to #detail-modal only).
# CSS-only: cannot affect other modals or any review JS.
set -uo pipefail
if [ ! -f templates/marketplace.html ]; then echo "X Run from project root (needs templates/marketplace.html)."; exit 1; fi
BK="reviews_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK/templates"; cp templates/marketplace.html "$BK/templates/marketplace.html"
echo ">> Backup: $BK/templates/marketplace.html"
cat > .rev.py << 'REV_PY_EOF'
import sys
PATH='templates/marketplace.html'
s=open(PATH,encoding='utf-8').read()
if 'reviews dialog redesign v1' in s:
    print('   - reviews dialog redesign already applied'); sys.exit(0)
if 'id="detail-modal"' not in s:
    print('   X #detail-modal not found -> is this marketplace.html? untouched'); sys.exit(1)

CSS = '''        /* ===== reviews dialog redesign v1 ===== */
        #detail-modal .mc{ border-radius:24px; box-shadow:0 40px 90px -30px rgba(6,28,15,.55) }
        #detail-modal .detail-hero{ height:240px; border-radius:18px; background:linear-gradient(135deg,#ecfdf5,#d1fae5); box-shadow:inset 0 0 0 1px rgba(16,40,28,.06) }
        #detail-modal .detail-hero img{ transition:transform .5s cubic-bezier(.16,1,.3,1) }
        #detail-modal .detail-hero:hover img{ transform:scale(1.04) }
        #detail-modal .detail-hero .ini-lg{ background:linear-gradient(135deg,var(--g500),var(--g700)); -webkit-background-clip:text; background-clip:text; color:transparent }
        #detail-modal .detail-rating{ background:linear-gradient(135deg,#ffffff,#fbfdfb); border:1px solid var(--line); border-radius:18px; padding:1.25rem 1.4rem; gap:1.6rem; box-shadow:0 14px 36px -28px rgba(20,40,25,.5) }
        #detail-modal #detail-avg{ font-family:Fraunces,serif; font-size:3.1rem !important; line-height:1 !important; background:linear-gradient(135deg,var(--g500),var(--g700)); -webkit-background-clip:text; background-clip:text; color:transparent !important }
        #detail-modal #detail-avgstars .stars{ font-size:1rem; letter-spacing:1px }
        #detail-modal #detail-bars{ padding-left:1.6rem; border-left:1px solid var(--line) }
        #detail-modal .review-form{ border:1px solid var(--line); border-radius:18px; padding:1.3rem; background:linear-gradient(180deg,#fbfdfb,#ffffff); box-shadow:0 14px 36px -28px rgba(20,40,25,.5) }
        #detail-modal .review-form h4{ font-family:Fraunces,serif }
        #detail-modal .review-stars{ font-size:2.2rem; gap:.4rem }
        #detail-modal .review-stars span{ transition:transform .12s ease, color .12s ease; transform-origin:center bottom; filter:drop-shadow(0 2px 4px rgba(0,0,0,.06)) }
        #detail-modal .review-stars span:hover{ transform:scale(1.22) rotate(-4deg) }
        #detail-modal #review-comment{ border-radius:13px; min-height:84px }
        #detail-modal #review-submit{ width:auto; min-width:180px; padding:.72rem 1.4rem; border-radius:13px }
        #detail-modal .rev-card{ border:1px solid var(--line); border-radius:16px; padding:.95rem 1.05rem; background:#fff; box-shadow:0 8px 22px -18px rgba(20,40,25,.5); transition:transform .15s ease, box-shadow .15s ease, border-color .15s ease }
        #detail-modal .rev-card:hover{ transform:translateY(-2px); border-color:#bfe3cd; box-shadow:0 16px 34px -22px rgba(5,120,80,.4) }
        #detail-modal .rev-av{ width:42px; height:42px; box-shadow:0 0 0 3px rgba(16,185,129,.12); font-size:.95rem }
'''

i=s.find('</style>')
if i<0:
    print('   X no </style> -> untouched'); sys.exit(1)
s=s[:i]+CSS+s[i:]
open(PATH,'w',encoding='utf-8').write(s)
# brace balance sanity on the injected block
if CSS.count('{')!=CSS.count('}'):
    print('   X brace mismatch'); sys.exit(1)
print('   OK reviews dialog restyled (%d rules)'%CSS.count('{'))
REV_PY_EOF
python3 .rev.py; RC=$?
rm -f .rev.py
if [ $RC -ne 0 ]; then echo "X failed; restore: cp -a $BK/templates/marketplace.html templates/marketplace.html"; exit 1; fi
echo ">> Done. Hard-refresh marketplace.html and open any product. Rollback: cp -a $BK/templates/marketplace.html templates/marketplace.html"
