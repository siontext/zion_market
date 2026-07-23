#!/usr/bin/env bash
# zion-market 릴리스 스크립트 (다중 플러그인 지원)
#
# 하는 일:
#   1) plugins/* 중 "변경된(=커밋 안 된 변경이 있는)" 플러그인을 찾아 patch 버전 +1
#      - 아직 설치/등록 안 된 새 플러그인도 릴리스 대상에 포함
#   2) 각 plugin.json 버전을 marketplace.json 항목과 동기화
#   3) git commit + push
#   4) 마켓플레이스 갱신 + 각 플러그인 설치/업데이트(캐시 반영)
#
# 사용법:
#   ./scripts/release.sh                 # 변경된 플러그인 자동 감지 후 patch +1
#   ./scripts/release.sh linkedin        # 특정 플러그인만 강제 릴리스
#   ./scripts/release.sh linkedin 0.2.0  # 특정 플러그인을 지정 버전으로
#
# 주의: 스킬/플러그인 내용을 수정한 뒤 이 스크립트를 실행하면
#       버전이 올라가면서 설치본 캐시까지 자동 반영됩니다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKET_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
MARKET_NAME="$(python3 -c "import json;print(json.load(open('$MARKET_JSON'))['name'])")"
cd "$REPO_ROOT"

# 릴리스 대상 플러그인 목록 결정
declare -a TARGETS
FORCE_VERSION=""
if [[ $# -ge 1 ]]; then
  TARGETS=("$1")
  [[ $# -ge 2 ]] && FORCE_VERSION="$2"
else
  # 커밋 안 된 변경(추적/미추적 모두)이 있는 플러그인 자동 감지
  for dir in plugins/*/; do
    name="$(basename "$dir")"
    if [[ -n "$(git status --porcelain -- "$dir")" ]]; then
      TARGETS+=("$name")
    fi
  done
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "변경된 플러그인이 없습니다. 릴리스할 것이 없습니다."
  exit 0
fi

# 각 대상 플러그인 버전 범프 + marketplace.json 동기화
for name in "${TARGETS[@]}"; do
  PLUGIN_JSON="$REPO_ROOT/plugins/$name/.claude-plugin/plugin.json"
  if [[ ! -f "$PLUGIN_JSON" ]]; then
    echo "⚠️  plugins/$name/.claude-plugin/plugin.json 없음 — 건너뜀"
    continue
  fi
  CURRENT="$(python3 -c "import json;print(json.load(open('$PLUGIN_JSON'))['version'])")"
  if [[ -n "$FORCE_VERSION" ]]; then
    NEXT="$FORCE_VERSION"
  else
    NEXT="$(python3 -c "v='$CURRENT'.split('.');v[2]=str(int(v[2])+1);print('.'.join(v))")"
  fi
  echo "[$name] $CURRENT -> $NEXT"

  # plugin.json + marketplace.json 동기화 (JSON 파싱으로 안전 교체)
  python3 - "$PLUGIN_JSON" "$MARKET_JSON" "$name" "$NEXT" <<'PY'
import json, sys
plugin_path, market_path, name, ver = sys.argv[1:5]
d = json.load(open(plugin_path)); d['version'] = ver
json.dump(d, open(plugin_path, 'w'), ensure_ascii=False, indent=2); open(plugin_path,'a').write('\n')
m = json.load(open(market_path))
for p in m.get('plugins', []):
    if p.get('name') == name:
        p['version'] = ver
json.dump(m, open(market_path, 'w'), ensure_ascii=False, indent=2); open(market_path,'a').write('\n')
PY
done

# 커밋 + 푸시
git add -A
git commit -q -m "chore: 릴리스 ${TARGETS[*]} (v범프)"
if git remote get-url origin >/dev/null 2>&1; then
  git push -q origin HEAD
  echo "✔ git push 완료"
else
  echo "· 원격(origin) 없음 — push 생략"
fi

# 마켓플레이스 갱신 (한 번)
claude plugin marketplace update "$MARKET_NAME"

# 각 플러그인 설치 or 업데이트 (설치 안 돼 있으면 install, 돼 있으면 update)
for name in "${TARGETS[@]}"; do
  ref="$name@$MARKET_NAME"
  if claude plugin update "$ref" 2>/dev/null; then
    :
  else
    echo "· $ref 미설치 — install 시도"
    claude plugin install "$ref"
  fi
done

echo ""
echo "✅ 릴리스 완료: ${TARGETS[*]}. 새 내용을 적용하려면 Claude Code를 재시작하세요."
