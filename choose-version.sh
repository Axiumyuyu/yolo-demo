#!/usr/bin/env bash
# choose_versions_for_poetry.sh
# 用法: ./choose_versions_for_poetry.sh /usr/bin/python3.8 pkgs.txt
# pkgs.txt 每行一个包名（可带 extras，如 requests[security]），可有注释/空行。

set -euo pipefail

PYBIN=${1:-}
PKGFILE=${2:-}

if [[ -z "$PYBIN" || -z "$PKGFILE" ]]; then
  echo "Usage: $0 /path/to/python requirements.txt"
  exit 2
fi
if [[ ! -x "$PYBIN" ]]; then
  echo "Python not executable: $PYBIN"
  exit 3
fi
if [[ ! -f "$PKGFILE" ]]; then
  echo "Packages file not found: $PKGFILE"
  exit 4
fi

TMPVENV=$(mktemp -d /tmp/ptenv.XXXX)
"$PYBIN" -m venv "$TMPVENV"
# shellcheck disable=SC1090
source "$TMPVENV/bin/activate"

pip install --upgrade pip setuptools wheel

while IFS= read -r line || [[ -n "$line" ]]; do
  pkg=$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  [[ -z "$pkg" || "${pkg:0:1}" == "#" ]] && continue

  echo "==> resolving: $pkg (using pip in temp venv)"
  # 让 pip 安装（会选择与当前 Python 兼容的版本）
  pip install --no-deps --disable-pip-version-check "$pkg" || {
    # 如果单独不装（--no-deps）失败，再尝试带 deps（有些包在 wheel 中需要依赖解析）
    pip install --disable-pip-version-check "$pkg"
  }

  # 获取安装的名字和版本（use pip show）
  name=$(python - <<PY
import pkgutil, sys, re
s="$pkg"
# try to get canonical name (strip extras)
s = re.sub(r'\[.*\]$', '', s)
print(s)
PY
)
  ver=$(pip show "$name" 2>/dev/null | awk '/^Version: /{print $2}')
  if [[ -z "$ver" ]]; then
    echo "Warning: cannot determine installed version for $pkg, skipping..."
    continue
  fi

  echo " -> found $name==$ver ; adding to poetry"
  poetry add "${name}==${ver}"

  # 清理安装，避免占用过多空间
  pip uninstall -y "$name" || true
done < "$PKGFILE"

deactivate
rm -rf "$TMPVENV"
echo "Done."
