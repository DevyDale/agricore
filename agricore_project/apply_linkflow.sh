#!/usr/bin/env bash
# Phase 3a: app-less rider one-time SMS link. Adds DeliveryJob.access_* fields (+migration),
# seller "send link" action, 3 public token endpoints, the no-login rider page, and the
# seller UI button. The link alone cannot fake a handover: pickup still needs the seller
# code and delivery still needs the buyer code.
set -uo pipefail
if [ ! -f manage.py ]; then echo "X Run from the Django project root (where manage.py is)."; exit 1; fi

UP=""
for c in urls.py agricore_project/urls.py agricore_project/agricore_project/urls.py; do
  if [ -f "$c" ] && grep -q "logistics.api.views import" "$c"; then UP="$c"; break; fi
done
if [ -z "$UP" ]; then
  for c in urls.py agricore_project/urls.py agricore_project/agricore_project/urls.py; do
    if [ -f "$c" ]; then UP="$c"; break; fi
  done
fi
if [ -z "$UP" ]; then echo "X Could not locate urls.py."; exit 1; fi

RL_EXISTED=0; [ -f templates/rider_link.html ] && RL_EXISTED=1
BK="linkflow_backup_$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BK"
cp -a logistics/models.py "$BK/models.py"
cp -a logistics/api/views.py "$BK/views.py"
cp -a templates/digital_store.html "$BK/digital_store.html"
cp -a "$UP" "$BK/urls.py"
echo ">> Backup: $BK/  (urls.py = $UP)"

cat > .linkflow.py << 'LINKW_EOF'
import sys, os, ast, base64

def parse_or_die(p):
    try: ast.parse(open(p,encoding='utf-8').read())
    except SyntaxError as e:
        print('   X %s invalid: %s'%(p,e)); sys.exit(1)

RIDER_HTML_B64 = "PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CiAgPG1ldGEgY2hhcnNldD0iVVRGLTgiPgogIDxtZXRhIG5hbWU9InZpZXdwb3J0IiBjb250ZW50PSJ3aWR0aD1kZXZpY2Utd2lkdGgsIGluaXRpYWwtc2NhbGU9MS4wIj4KICA8dGl0bGU+QWdyaWNvcmUgRGVsaXZlcnk8L3RpdGxlPgogIDxzY3JpcHQgc3JjPSJodHRwczovL2Nkbi50YWlsd2luZGNzcy5jb20iPjwvc2NyaXB0PgogIDxsaW5rIHJlbD0ic3R5bGVzaGVldCIgaHJlZj0iaHR0cHM6Ly9jZG5qcy5jbG91ZGZsYXJlLmNvbS9hamF4L2xpYnMvZm9udC1hd2Vzb21lLzYuNS4xL2Nzcy9hbGwubWluLmNzcyI+CiAgPHN0eWxlPgogICAgYm9keSB7IGJhY2tncm91bmQ6I2YwZmRmNDsgfQogICAgLmNhcmQgeyBtYXgtd2lkdGg6NDgwcHg7IG1hcmdpbjowIGF1dG87IH0KICAgIC5pbnAgeyB3aWR0aDoxMDAlOyBib3JkZXI6MXB4IHNvbGlkICNkMWQ1ZGI7IGJvcmRlci1yYWRpdXM6MTJweDsgcGFkZGluZzouOHJlbSAxcmVtOyBmb250LXNpemU6MS40cmVtOyBsZXR0ZXItc3BhY2luZzouMjVlbTsgdGV4dC1hbGlnbjpjZW50ZXI7IGZvbnQtd2VpZ2h0OjgwMDsgY29sb3I6IzA2NWY0NjsgfQogICAgLmlucDpmb2N1cyB7IG91dGxpbmU6bm9uZTsgYm9yZGVyLWNvbG9yOiMxMGI5ODE7IGJveC1zaGFkb3c6MCAwIDAgM3B4IHJnYmEoMTYsMTg1LDEyOSwuMjUpOyB9CiAgICAuYnRuIHsgd2lkdGg6MTAwJTsgcGFkZGluZzouODVyZW07IGJvcmRlcjpub25lOyBib3JkZXItcmFkaXVzOjEycHg7IGZvbnQtd2VpZ2h0OjgwMDsgZm9udC1zaXplOjFyZW07IGN1cnNvcjpwb2ludGVyOyB9CiAgPC9zdHlsZT4KPC9oZWFkPgo8Ym9keSBjbGFzcz0ibWluLWgtc2NyZWVuIHAtNCI+CiAgPGRpdiBjbGFzcz0iY2FyZCBwdC02Ij4KICAgIDxkaXYgY2xhc3M9ImZsZXggaXRlbXMtY2VudGVyIGdhcC0yIG1iLTQiPgogICAgICA8ZGl2IGNsYXNzPSJ3LTkgaC05IHJvdW5kZWQteGwgYmctZW1lcmFsZC02MDAgdGV4dC13aGl0ZSBncmlkIHBsYWNlLWl0ZW1zLWNlbnRlciI+PGkgY2xhc3M9ImZhcyBmYS1zZWVkbGluZyI+PC9pPjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJmb250LWV4dHJhYm9sZCB0ZXh0LWVtZXJhbGQtODAwIHRleHQtbGciPkFncmljb3JlIERlbGl2ZXJ5PC9kaXY+CiAgICA8L2Rpdj4KICAgIDxkaXYgaWQ9InJvb3QiIGNsYXNzPSJiZy13aGl0ZSByb3VuZGVkLTJ4bCBzaGFkb3ctc20gYm9yZGVyIGJvcmRlci1lbWVyYWxkLTEwMCBwLTUiPgogICAgICA8ZGl2IGlkPSJsb2FkaW5nIiBjbGFzcz0idGV4dC1jZW50ZXIgdGV4dC1ncmF5LTUwMCBweS04Ij48aSBjbGFzcz0iZmFzIGZhLXNwaW5uZXIgZmEtc3BpbiI+PC9pPiBMb2FkaW5nIHlvdXIgZGVsaXZlcnnigKY8L2Rpdj4KICAgIDwvZGl2PgogICAgPHAgY2xhc3M9InRleHQtY2VudGVyIHRleHQteHMgdGV4dC1ncmF5LTQwMCBtdC00Ij5UaGlzIGxpbmsgaXMganVzdCBmb3IgeW91LiBEbyBub3Qgc2hhcmUgeW91ciBjb2Rlcy48L3A+CiAgPC9kaXY+CgogIDxzY3JpcHQ+CiAgICB2YXIgQVBJID0gd2luZG93LmxvY2F0aW9uLm9yaWdpbiArICcvYXBpJzsKICAgIHZhciBUT0tFTiA9IG5ldyBVUkxTZWFyY2hQYXJhbXMod2luZG93LmxvY2F0aW9uLnNlYXJjaCkuZ2V0KCd0JykgfHwgJyc7CiAgICB2YXIgcm9vdCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdyb290Jyk7CgogICAgZnVuY3Rpb24gZXNjKHMpeyByZXR1cm4gU3RyaW5nKHMgPT0gbnVsbCA/ICcnIDogcykucmVwbGFjZSgvWyY8PiInXS9nLCBmdW5jdGlvbihjKXsgcmV0dXJuICh7JyYnOicmYW1wOycsJzwnOicmbHQ7JywnPic6JyZndDsnLCciJzonJnF1b3Q7JywiJyI6JyYjMzk7J31bY10pOyB9KTsgfQogICAgZnVuY3Rpb24gbW9uZXkodiwgY3VyKXsgcmV0dXJuIChjdXIgfHwgJ1VHWCcpICsgJyAnICsgZXNjKHYpOyB9CgogICAgYXN5bmMgZnVuY3Rpb24gYXBpKHBhdGgsIG9wdHMpewogICAgICB2YXIgciA9IGF3YWl0IGZldGNoKEFQSSArIHBhdGgsIG9wdHMgfHwge30pOwogICAgICB2YXIgZCA9IG51bGw7CiAgICAgIHRyeSB7IGQgPSBhd2FpdCByLmpzb24oKTsgfSBjYXRjaChlKSB7IGQgPSB7fTsgfQogICAgICBpZiAoIXIub2spIHsgdGhyb3cgbmV3IEVycm9yKChkICYmIGQuZGV0YWlsKSB8fCAoJ0Vycm9yICcgKyByLnN0YXR1cykpOyB9CiAgICAgIHJldHVybiBkOwogICAgfQoKICAgIGZ1bmN0aW9uIHJvdyhpY29uLCBsYWJlbCwgdmFsdWUpewogICAgICBpZiAoIXZhbHVlKSByZXR1cm4gJyc7CiAgICAgIHJldHVybiAnPGRpdiBjbGFzcz0iZmxleCBpdGVtcy1zdGFydCBnYXAtMiB0ZXh0LXNtIHRleHQtZ3JheS03MDAgbWItMiI+PGkgY2xhc3M9ImZhcyAnICsgaWNvbiArICcgdGV4dC1lbWVyYWxkLTYwMCBtdC0wLjUgdy00Ij48L2k+PGRpdj48c3BhbiBjbGFzcz0idGV4dC1ncmF5LTQwMCI+JyArIGxhYmVsICsgJzwvc3Bhbj48YnI+JyArIHZhbHVlICsgJzwvZGl2PjwvZGl2Pic7CiAgICB9CgogICAgZnVuY3Rpb24gcmVuZGVyKGpvYil7CiAgICAgIGlmICgham9iKSByZXR1cm47CiAgICAgIHZhciBjbG9zZWQgPSAoam9iLnN0YXR1cyA9PT0gJ2RlbGl2ZXJlZCcgfHwgam9iLnN0YXR1cyA9PT0gJ2NhbmNlbGxlZCcpOwogICAgICB2YXIgc2VsbGVyUGhvbmUgPSBqb2Iuc2VsbGVyX3Bob25lID8gKCc8YSBocmVmPSJ0ZWw6JyArIGVzYyhqb2Iuc2VsbGVyX3Bob25lKSArICciIGNsYXNzPSJ0ZXh0LWVtZXJhbGQtNzAwIHVuZGVybGluZSBmb250LXNlbWlib2xkIj4nICsgZXNjKGpvYi5zZWxsZXJfcGhvbmUpICsgJzwvYT4nKSA6ICcnOwogICAgICB2YXIgc2VsbGVyID0gKGpvYi5zZWxsZXJfbmFtZSB8fCAnJykgKyAoc2VsbGVyUGhvbmUgPyAoJyDCtyAnICsgc2VsbGVyUGhvbmUpIDogJycpOwoKICAgICAgdmFyIGh0bWwgPSAnPGRpdiBjbGFzcz0iZmxleCBpdGVtcy1jZW50ZXIganVzdGlmeS1iZXR3ZWVuIG1iLTMiPicKICAgICAgICArICc8ZGl2IGNsYXNzPSJmb250LWJvbGQgdGV4dC1ncmF5LTgwMCI+T3JkZXIgIycgKyBlc2Moam9iLm9yZGVyX2lkKSArICc8L2Rpdj4nCiAgICAgICAgKyAnPHNwYW4gY2xhc3M9InRleHQteHMgZm9udC1zZW1pYm9sZCBweC0yIHB5LTEgcm91bmRlZC1mdWxsIGJnLWVtZXJhbGQtNTAgdGV4dC1lbWVyYWxkLTcwMCI+JyArIGVzYyhqb2Iuc3RhdHVzKSArICc8L3NwYW4+JwogICAgICAgICsgJzwvZGl2Pic7CgogICAgICBodG1sICs9IHJvdygnZmEtdXNlci10aWUnLCAnU2VsbGVyJywgc2VsbGVyIHx8ICfigJQnKTsKICAgICAgaHRtbCArPSByb3coJ2ZhLWxvY2F0aW9uLWRvdCcsICdQaWNrIHVwIGF0JywgZXNjKGpvYi5waWNrdXBfbG9jYXRpb24pIHx8ICfigJQnKTsKICAgICAgaHRtbCArPSByb3coJ2ZhLWZsYWctY2hlY2tlcmVkJywgJ0RlbGl2ZXIgdG8nLCBlc2Moam9iLmRyb3BfbG9jYXRpb24pIHx8ICfigJQnKTsKICAgICAgaHRtbCArPSByb3coJ2ZhLWNvaW5zJywgJ1lvdXIgZmVlJywgbW9uZXkoam9iLm9mZmVyZWRfZmVlLCBqb2IuY3VycmVuY3kpKTsKCiAgICAgIGh0bWwgKz0gJzxkaXYgY2xhc3M9ImJvcmRlci10IGJvcmRlci1ncmF5LTEwMCBtdC0zIHB0LTQiPic7CgogICAgICBpZiAoam9iLm5leHRfYWN0aW9uID09PSAncGlja3VwJykgewogICAgICAgIGh0bWwgKz0gJzxwIGNsYXNzPSJ0ZXh0LXNtIGZvbnQtc2VtaWJvbGQgdGV4dC1ncmF5LTgwMCBtYi0xIj5Db25maXJtIHBpY2t1cDwvcD4nCiAgICAgICAgICArICc8cCBjbGFzcz0idGV4dC14cyB0ZXh0LWdyYXktNTAwIG1iLTMiPkFzayB0aGUgc2VsbGVyIGZvciB0aGUgcGlja3VwIGNvZGUgYW5kIGVudGVyIGl0IGhlcmUgd2hlbiB5b3UgY29sbGVjdCB0aGUgZ29vZHMuPC9wPicKICAgICAgICAgICsgJzxpbnB1dCBpZD0iY29kZSIgY2xhc3M9ImlucCBtYi0zIiBpbnB1dG1vZGU9Im51bWVyaWMiIHBsYWNlaG9sZGVyPSItLS0tLS0iPicKICAgICAgICAgICsgJzxidXR0b24gY2xhc3M9ImJ0biBiZy1lbWVyYWxkLTYwMCB0ZXh0LXdoaXRlIiBvbmNsaWNrPSJkb1BpY2t1cCgpIj48aSBjbGFzcz0iZmFzIGZhLWJveCI+PC9pPiBJIGhhdmUgY29sbGVjdGVkIHRoZSBnb29kczwvYnV0dG9uPicKICAgICAgICAgICsgJzxkaXYgaWQ9Im1zZyIgY2xhc3M9InRleHQtc20gdGV4dC1jZW50ZXIgbXQtMyI+PC9kaXY+JzsKICAgICAgfSBlbHNlIGlmIChqb2IubmV4dF9hY3Rpb24gPT09ICdkZWxpdmVyJykgewogICAgICAgIGh0bWwgKz0gJzxwIGNsYXNzPSJ0ZXh0LXNtIGZvbnQtc2VtaWJvbGQgdGV4dC1ncmF5LTgwMCBtYi0xIj5Db25maXJtIGRlbGl2ZXJ5PC9wPicKICAgICAgICAgICsgJzxwIGNsYXNzPSJ0ZXh0LXhzIHRleHQtZ3JheS01MDAgbWItMyI+QXNrIHRoZSBidXllciBmb3IgdGhlaXIgZGVsaXZlcnkgY29kZSBhbmQgZW50ZXIgaXQgaGVyZSBvbmNlIHlvdSBoYW5kIG92ZXIgdGhlIGdvb2RzLjwvcD4nCiAgICAgICAgICArICc8aW5wdXQgaWQ9ImNvZGUiIGNsYXNzPSJpbnAgbWItMyIgaW5wdXRtb2RlPSJudW1lcmljIiBwbGFjZWhvbGRlcj0iLS0tLS0tIj4nCiAgICAgICAgICArICc8YnV0dG9uIGNsYXNzPSJidG4gYmctYmx1ZS02MDAgdGV4dC13aGl0ZSIgb25jbGljaz0iZG9EZWxpdmVyKCkiPjxpIGNsYXNzPSJmYXMgZmEtY2lyY2xlLWNoZWNrIj48L2k+IEkgaGF2ZSBkZWxpdmVyZWQgdGhlIGdvb2RzPC9idXR0b24+JwogICAgICAgICAgKyAnPGRpdiBpZD0ibXNnIiBjbGFzcz0idGV4dC1zbSB0ZXh0LWNlbnRlciBtdC0zIj48L2Rpdj4nOwogICAgICB9IGVsc2UgaWYgKGpvYi5zdGF0dXMgPT09ICdkZWxpdmVyZWQnKSB7CiAgICAgICAgaHRtbCArPSAnPGRpdiBjbGFzcz0idGV4dC1jZW50ZXIgdGV4dC1lbWVyYWxkLTcwMCBweS00Ij48aSBjbGFzcz0iZmFzIGZhLWNpcmNsZS1jaGVjayB0ZXh0LTN4bCI+PC9pPjxwIGNsYXNzPSJtdC0yIGZvbnQtc2VtaWJvbGQiPkRlbGl2ZXJlZC4gVGhhbmsgeW91ITwvcD48L2Rpdj4nOwogICAgICB9IGVsc2UgewogICAgICAgIGh0bWwgKz0gJzxkaXYgY2xhc3M9InRleHQtY2VudGVyIHRleHQtZ3JheS01MDAgcHktNCI+PGkgY2xhc3M9ImZhcyBmYS1jaXJjbGUtaW5mbyB0ZXh0LTJ4bCI+PC9pPjxwIGNsYXNzPSJtdC0yIj5UaGlzIGRlbGl2ZXJ5IGlzIGNsb3NlZC48L3A+PC9kaXY+JzsKICAgICAgfQogICAgICBodG1sICs9ICc8L2Rpdj4nOwogICAgICByb290LmlubmVySFRNTCA9IGh0bWw7CiAgICB9CgogICAgZnVuY3Rpb24gc2V0TXNnKHRleHQsIG9rKXsKICAgICAgdmFyIG0gPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbXNnJyk7CiAgICAgIGlmIChtKSBtLmlubmVySFRNTCA9ICc8c3BhbiBjbGFzcz0iJyArIChvayA/ICd0ZXh0LWVtZXJhbGQtNzAwJyA6ICd0ZXh0LXJlZC02MDAnKSArICcgZm9udC1zZW1pYm9sZCI+JyArIGVzYyh0ZXh0KSArICc8L3NwYW4+JzsKICAgIH0KCiAgICBhc3luYyBmdW5jdGlvbiBsb2FkKCl7CiAgICAgIGlmICghVE9LRU4pIHsgcm9vdC5pbm5lckhUTUwgPSAnPGRpdiBjbGFzcz0idGV4dC1jZW50ZXIgdGV4dC1yZWQtNjAwIHB5LTYiPlRoaXMgbGluayBpcyBtaXNzaW5nIGl0cyBjb2RlLjwvZGl2Pic7IHJldHVybjsgfQogICAgICB0cnkgewogICAgICAgIHZhciBqb2IgPSBhd2FpdCBhcGkoJy9yaWRlci1saW5rLycgKyBlbmNvZGVVUklDb21wb25lbnQoVE9LRU4pICsgJy8nKTsKICAgICAgICByZW5kZXIoam9iKTsKICAgICAgfSBjYXRjaCAoZSkgewogICAgICAgIHJvb3QuaW5uZXJIVE1MID0gJzxkaXYgY2xhc3M9InRleHQtY2VudGVyIHRleHQtcmVkLTYwMCBweS02Ij48aSBjbGFzcz0iZmFzIGZhLXRyaWFuZ2xlLWV4Y2xhbWF0aW9uIHRleHQtMnhsIj48L2k+PHAgY2xhc3M9Im10LTIiPicgKyBlc2MoZS5tZXNzYWdlIHx8ICdUaGlzIGxpbmsgaXMgbm90IHZhbGlkLicpICsgJzwvcD48L2Rpdj4nOwogICAgICB9CiAgICB9CgogICAgd2luZG93LmRvUGlja3VwID0gYXN5bmMgZnVuY3Rpb24oKXsKICAgICAgdmFyIGNvZGUgPSAoZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2NvZGUnKS52YWx1ZSB8fCAnJykudHJpbSgpOwogICAgICBpZiAoIWNvZGUpIHsgc2V0TXNnKCdFbnRlciB0aGUgcGlja3VwIGNvZGUuJywgZmFsc2UpOyByZXR1cm47IH0KICAgICAgc2V0TXNnKCdDaGVja2luZ+KApicsIHRydWUpOwogICAgICB0cnkgewogICAgICAgIGF3YWl0IGFwaSgnL3JpZGVyLWxpbmsvJyArIGVuY29kZVVSSUNvbXBvbmVudChUT0tFTikgKyAnL3BpY2t1cC8nLCB7CiAgICAgICAgICBtZXRob2Q6ICdQT1NUJywgaGVhZGVyczogeyAnQ29udGVudC1UeXBlJzogJ2FwcGxpY2F0aW9uL2pzb24nIH0sIGJvZHk6IEpTT04uc3RyaW5naWZ5KHsgcGlja3VwX2NvZGU6IGNvZGUgfSkKICAgICAgICB9KTsKICAgICAgICBhd2FpdCBsb2FkKCk7CiAgICAgIH0gY2F0Y2ggKGUpIHsgc2V0TXNnKGUubWVzc2FnZSB8fCAnQ291bGQgbm90IGNvbmZpcm0gcGlja3VwLicsIGZhbHNlKTsgfQogICAgfTsKCiAgICB3aW5kb3cuZG9EZWxpdmVyID0gYXN5bmMgZnVuY3Rpb24oKXsKICAgICAgdmFyIGNvZGUgPSAoZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2NvZGUnKS52YWx1ZSB8fCAnJykudHJpbSgpOwogICAgICBpZiAoIWNvZGUpIHsgc2V0TXNnKCdFbnRlciB0aGUgZGVsaXZlcnkgY29kZS4nLCBmYWxzZSk7IHJldHVybjsgfQogICAgICBzZXRNc2coJ0NoZWNraW5n4oCmJywgdHJ1ZSk7CiAgICAgIHRyeSB7CiAgICAgICAgYXdhaXQgYXBpKCcvcmlkZXItbGluay8nICsgZW5jb2RlVVJJQ29tcG9uZW50KFRPS0VOKSArICcvZGVsaXZlci8nLCB7CiAgICAgICAgICBtZXRob2Q6ICdQT1NUJywgaGVhZGVyczogeyAnQ29udGVudC1UeXBlJzogJ2FwcGxpY2F0aW9uL2pzb24nIH0sIGJvZHk6IEpTT04uc3RyaW5naWZ5KHsgb3RwOiBjb2RlIH0pCiAgICAgICAgfSk7CiAgICAgICAgYXdhaXQgbG9hZCgpOwogICAgICB9IGNhdGNoIChlKSB7IHNldE1zZyhlLm1lc3NhZ2UgfHwgJ0NvdWxkIG5vdCBjb25maXJtIGRlbGl2ZXJ5LicsIGZhbHNlKTsgfQogICAgfTsKCiAgICBsb2FkKCk7CiAgPC9zY3JpcHQ+CjwvYm9keT4KPC9odG1sPgo="

# ---------- 1) logistics/models.py ----------
MP='logistics/models.py'; m=open(MP,encoding='utf-8').read()
if 'access_token' not in m:
    OLD='''    pickup_code = models.CharField(max_length=8, blank=True, default="")
    notes = models.TextField(blank=True, default="")'''
    NEW='''    pickup_code = models.CharField(max_length=8, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    # ---- App-less rider one-time link (Phase 3): token-authorised, no login ----
    access_token = models.CharField(max_length=64, blank=True, default="", db_index=True)
    access_phone = models.CharField(max_length=20, blank=True, default="")
    access_name = models.CharField(max_length=120, blank=True, default="")'''
    if OLD not in m: print('   X models anchor not found'); sys.exit(1)
    open(MP,'w',encoding='utf-8').write(m.replace(OLD,NEW,1)); parse_or_die(MP)
    print('   OK logistics/models.py: access_token/phone/name on DeliveryJob')
else:
    print('   - logistics/models.py already has access fields')

# ---------- 2) logistics/api/views.py ----------
VP='logistics/api/views.py'; v=open(VP,encoding='utf-8').read()
if 'class RiderLinkView' not in v:
    I_OLD='from rest_framework.permissions import IsAuthenticated\n'
    I_NEW='from rest_framework.permissions import IsAuthenticated, AllowAny\nfrom rest_framework.views import APIView\n'
    if I_OLD not in v: print('   X logistics views import anchor not found'); sys.exit(1)
    v=v.replace(I_OLD,I_NEW,1)
    C_OLD='''    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):'''
    SEND='''    @action(detail=True, methods=["post"])
    def send_link(self, request, pk=None):
        """Seller assigns this delivery to a rider phone and texts a one-time, no-login
        link to work the job. The link cannot fake a handover on its own: pickup still
        needs the seller pickup code and delivery still needs the buyer code."""
        import secrets
        from utils.sms import send_sms, normalize_ug
        job = self.get_object()
        if job.created_by_id != request.user.id:
            return Response({"detail": "Only the seller can send a delivery link."}, status=status.HTTP_403_FORBIDDEN)
        if job.status not in ("open", "accepted"):
            return Response({"detail": f"Cannot send a link from status: {job.status}."}, status=status.HTTP_400_BAD_REQUEST)
        phone = normalize_ug(request.data.get("phone", ""))
        if not phone:
            return Response({"detail": "Enter the rider phone number."}, status=status.HTTP_400_BAD_REQUEST)
        name = str(request.data.get("name", "") or "").strip()[:120]
        if not job.access_token:
            job.access_token = secrets.token_urlsafe(32)
        job.access_phone = phone
        job.access_name = name
        job.status = "accepted"
        job.accepted_at = job.accepted_at or timezone.now()
        job.save(update_fields=["access_token", "access_phone", "access_name", "status", "accepted_at", "updated_at"])
        link = request.build_absolute_uri(f"/rider_link.html?t={job.access_token}")
        msg = f"Agricore: you have a delivery to handle. Open {link} to start. The seller will give you a pickup code."
        sms_sent = False
        try:
            sms_sent = bool(send_sms(phone, msg))
        except Exception:
            sms_sent = False
        return Response({"detail": "Link sent to the rider.", "sms_sent": sms_sent, "link": link, "job": self.get_serializer(job).data})

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):'''
    if C_OLD not in v: print('   X logistics cancel anchor not found'); sys.exit(1)
    v=v.replace(C_OLD,SEND,1)

    APPEND='''def _job_for_token(token):
    if not token:
        return None
    return (
        DeliveryJob.objects
        .select_related("order", "order__store", "escrow")
        .filter(access_token=token)
        .first()
    )


class RiderLinkView(APIView):
    """Public, token-authorised view of one delivery job for an app-less rider."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        store = getattr(job.order, "store", None)
        if job.status == "accepted":
            nxt = "pickup"
        elif job.status == "picked_up":
            nxt = "deliver"
        else:
            nxt = "none"
        return Response({
            "order_id": job.order_id,
            "status": job.status,
            "next_action": nxt,
            "vehicle_type_required": job.vehicle_type_required,
            "pickup_location": job.pickup_location,
            "drop_location": job.drop_location,
            "offered_fee": str(job.offered_fee),
            "currency": job.currency,
            "rider_name": job.access_name,
            "seller_name": (getattr(store, "owner_name", "") or "") if store else "",
            "seller_phone": (getattr(store, "owner_phone", "") or "") if store else "",
        })


class RiderLinkPickupView(APIView):
    """Rider confirms pickup with the seller pickup code; fires the buyer delivery code."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request, token=None):
        job = _job_for_token(token)
        if job is None:
            return Response({"detail": "This link is not valid."}, status=status.HTTP_404_NOT_FOUND)
        if job.status != "accepted":
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
        return Response({"detail": "Picked up. The buyer has been sent their delivery code.", "sms_sent": sms_sent, "status": job.status})


class RiderLinkDeliverView(APIView):
    """Rider confirms delivery with the buyer code; starts the dispute window."""
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request, token=None):
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
        return Response({"detail": "Delivery confirmed. Thank you!", "status": job.status})
'''
    if not v.endswith('\n'): v+='\n'
    v=v+'\n\n'+APPEND
    open(VP,'w',encoding='utf-8').write(v); parse_or_die(VP)
    print('   OK logistics/api/views.py: send_link + 3 token endpoints')
else:
    print('   - logistics/api/views.py already has token endpoints')

# ---------- 3) urls.py ----------
UP='urls.py'
if not os.path.exists(UP):
    for cand in ['agricore_project/urls.py','agricore_project/agricore_project/urls.py']:
        if os.path.exists(cand): UP=cand; break
u=open(UP,encoding='utf-8').read()
if 'rider-link' not in u:
    IMP_OLD='from logistics.api.views import TransporterViewSet, DeliveryJobViewSet, TransporterReviewViewSet'
    IMP_NEW=IMP_OLD+', RiderLinkView, RiderLinkPickupView, RiderLinkDeliverView'
    if IMP_OLD not in u: print('   X urls logistics import anchor not found'); sys.exit(1)
    u=u.replace(IMP_OLD,IMP_NEW,1)
    P_OLD="    path('api/', include(router.urls)),"
    P_NEW=("    path('api/', include(router.urls)),\n"
           "    path('api/rider-link/<str:token>/', RiderLinkView.as_view()),\n"
           "    path('api/rider-link/<str:token>/pickup/', RiderLinkPickupView.as_view()),\n"
           "    path('api/rider-link/<str:token>/deliver/', RiderLinkDeliverView.as_view()),")
    if P_OLD not in u: print('   X urls router-include anchor not found'); sys.exit(1)
    u=u.replace(P_OLD,P_NEW,1)
    open(UP,'w',encoding='utf-8').write(u); parse_or_die(UP)
    print('   OK %s: rider-link routes + imports' % UP)
else:
    print('   - urls.py already has rider-link routes')

# ---------- 4) templates/rider_link.html ----------
RP='templates/rider_link.html'
if not os.path.exists(RP):
    open(RP,'wb').write(base64.b64decode(RIDER_HTML_B64))
    print('   OK templates/rider_link.html created')
else:
    print('   - templates/rider_link.html already exists (left as-is)')

# ---------- 5) templates/digital_store.html ----------
DP='templates/digital_store.html'; d=open(DP,encoding='utf-8').read()
if 'tj_send_link' not in d:
    F_OLD='''            html+='<div style="display:flex;gap:.5rem;justify-content:flex-end;margin-top:.9rem">';'''
    F_NEW='''            html+='<div style="margin-top:.9rem;padding-top:.8rem;border-top:1px solid #eef2f7">'
                +'<div style="font-size:.78rem;font-weight:700;color:#374151;margin-bottom:.4rem"><i class="fas fa-mobile-screen-button"></i> Send a one-time link to a rider by SMS</div>'
                +'<input id="tj_link_phone" type="tel" placeholder="07xx xxx xxx" style="width:100%;border:1px solid #d1d5db;border-radius:8px;padding:.5rem .7rem;font-size:.85rem;margin-bottom:.4rem">'
                +'<input id="tj_link_name" type="text" placeholder="Rider name (optional)" style="width:100%;border:1px solid #d1d5db;border-radius:8px;padding:.5rem .7rem;font-size:.85rem;margin-bottom:.4rem">'
                +'<button id="tj_send_link" type="button" style="width:100%;padding:.5rem;border:none;background:#2563eb;color:#fff;border-radius:8px;font-size:.82rem;font-weight:700;cursor:pointer"><i class="fas fa-paper-plane"></i> Send SMS link</button>'
                +'<div id="tj_link_out" style="font-size:.75rem;color:#6b7280;margin-top:.4rem"></div>'
                +'</div>';
            html+='<div style="display:flex;gap:.5rem;justify-content:flex-end;margin-top:.9rem">';'''
    if F_OLD not in d: print('   X digital_store buttons-row anchor not found'); sys.exit(1)
    d=d.replace(F_OLD,F_NEW,1)
    H_OLD="            m.box.querySelector('#tj_done').onclick=m.close;"
    H_NEW='''            m.box.querySelector('#tj_done').onclick=m.close;
            var sb=m.box.querySelector('#tj_send_link');
            if(sb){ sb.onclick=async function(){
                var ph=(m.box.querySelector('#tj_link_phone').value||'').trim();
                var nm=(m.box.querySelector('#tj_link_name').value||'').trim();
                var out=m.box.querySelector('#tj_link_out');
                if(!ph){ out.textContent='Enter the rider phone number.'; return; }
                sb.disabled=true; out.textContent='Sending...';
                try{
                    var r=await fetch(API_BASE+'/delivery-jobs/'+job.id+'/send_link/',{method:'POST',headers:{'Authorization':'Bearer '+(token||''),'Content-Type':'application/json'},body:JSON.stringify({phone:ph,name:nm})});
                    var dd=await r.json().catch(function(){return {};});
                    if(!r.ok){ out.textContent=(dd.detail||'Could not send link.'); sb.disabled=false; return; }
                    out.innerHTML='<span style="color:#047857;font-weight:700">Link sent'+(dd.sms_sent?' by SMS':'')+'.</span> Give the rider the pickup code above.';
                    toast('Link sent to the rider.','success');
                }catch(e){ out.textContent='Could not send link.'; sb.disabled=false; }
            }; }'''
    if H_OLD not in d: print('   X digital_store tj_done anchor not found'); sys.exit(1)
    d=d.replace(H_OLD,H_NEW,1)
    open(DP,'w',encoding='utf-8').write(d)
    print('   OK templates/digital_store.html: Send-SMS-link UI in tjShowJob')
else:
    print('   - templates/digital_store.html already has send-link UI')

print('DONE')
LINKW_EOF
python3 .linkflow.py; RC=$?
rm -f .linkflow.py
if [ $RC -ne 0 ]; then
  echo "X failed; restoring."
  cp -a "$BK/models.py" logistics/models.py
  cp -a "$BK/views.py" logistics/api/views.py
  cp -a "$BK/digital_store.html" templates/digital_store.html
  cp -a "$BK/urls.py" "$UP"
  [ $RL_EXISTED -eq 0 ] && rm -f templates/rider_link.html
  exit 1
fi

echo ""
echo ">> Code applied. Creating + applying the logistics migration (new DeliveryJob fields)..."
python manage.py makemigrations logistics && python manage.py migrate logistics
MRC=$?
if [ $MRC -ne 0 ]; then
  echo "!! Migration step did not finish. Your code is intact; run this manually:"
  echo "     python manage.py makemigrations logistics && python manage.py migrate logistics"
fi

echo ""
echo ">> Done. Restart the server; hard-refresh digital_store.html."
echo ">> Seller flow: open a held order -> Request a transporter -> Send a one-time link to a rider by SMS."
echo ">> Rider opens the texted link (no login), enters your pickup code, then the buyer's delivery code."
echo ">> Rollback: cp -a $BK/models.py logistics/models.py && cp -a $BK/views.py logistics/api/views.py && cp -a $BK/digital_store.html templates/digital_store.html && cp -a $BK/urls.py $UP" $([ $RL_EXISTED -eq 0 ] && echo "&& rm -f templates/rider_link.html")
