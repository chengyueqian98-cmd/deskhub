#!/bin/zsh
# 下载计数：GitHub 自带的统计（每个版本、每个安装包被下载了多少次），不需要在 App 里加任何追踪。
#   ./scripts/downloads.sh 你的用户名/仓库名
# 需要装好 gh（GitHub 命令行）并登录；公开仓库不登录也能用 curl 查。
set -e
REPO="${1:?用法：./scripts/downloads.sh 用户名/仓库名}"
if command -v gh >/dev/null 2>&1; then
  JSON=$(gh api "repos/$REPO/releases?per_page=100")
else
  JSON=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100")
fi
python3 - "$JSON" <<'EOF'
import json, sys
rels = json.loads(sys.argv[1])
total = 0
for r in rels:
    n = sum(a.get("download_count", 0) for a in r.get("assets", []))
    total += n
    print(f"{r.get('tag_name', '?'):<12} {r.get('published_at', '')[:10]}  {n:>6} 次")
print(f"{'合计':<12} {'':<10}  {total:>6} 次")
EOF
