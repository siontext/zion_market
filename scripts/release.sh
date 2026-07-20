#!/usr/bin/env bash
# linkedin 플러그인 릴리스 스크립트
#
# 하는 일:
#   1) plugin.json + marketplace.json 버전을 patch 단위로 +1 (또는 인자로 지정)
#   2) git commit + push
#   3) 마켓플레이스 + 설치된 플러그인 캐시 갱신
#
# 사용법:
#   ./scripts/release.sh              # patch 자동 증가 (0.1.1 -> 0.1.2)
#   ./scripts/release.sh 0.2.0        # 버전 직접 지정
#
# 주의: 스킬/플러그인 내용을 수정한 뒤 이 스크립트를 실행하면
#       버전이 올라가면서 설치본 캐시까지 자동 반영됩니다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$REPO_ROOT/plugins/linkedin/.claude-plugin/plugin.json"
MARKET_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

cd "$REPO_ROOT"

# 1. 현재 버전 읽기 + 다음 버전 계산
CURRENT="$(python3 -c "import json;print(json.load(open('$PLUGIN_JSON'))['version'])")"

if [[ $# -ge 1 ]]; then
  NEXT="$1"
else
  # patch 자동 증가
  NEXT="$(python3 -c "
v='$CURRENT'.split('.')
v[2]=str(int(v[2])+1)
print('.'.join(v))
")"
fi

echo "버전: $CURRENT -> $NEXT"

# 2. 두 파일의 버전 동기화 (JSON 파싱으로 안전하게 교체)
python3 - "$PLUGIN_JSON" "$NEXT" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d['version'] = ver
json.dump(d, open(path, 'w'), ensure_ascii=False, indent=2)
open(path, 'a').write('\n')
PY

python3 - "$MARKET_JSON" "$NEXT" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for p in d.get('plugins', []):
    if p.get('name') == 'linkedin':
        p['version'] = ver
json.dump(d, open(path, 'w'), ensure_ascii=False, indent=2)
open(path, 'a').write('\n')
PY

# 3. 커밋 + 푸시
git add -A
git commit -q -m "chore: linkedin 플러그인 릴리스 v$NEXT"
if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin HEAD
  echo "✔ git push 완료"
else
  echo "· 원격(origin) 없음 — push 생략"
fi

# 4. 마켓플레이스 + 플러그인 캐시 갱신
claude plugin marketplace update zion-market
claude plugin update linkedin@zion-market

echo ""
echo "✅ 릴리스 v$NEXT 완료. 새 규칙을 적용하려면 Claude Code를 재시작하세요."
