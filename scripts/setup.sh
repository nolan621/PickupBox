#!/usr/bin/env bash
#
# 把工程里的签名配置换成你自己的。
#
#   ./scripts/setup.sh                          交互式，跟着提示填
#   ./scripts/setup.sh --team ABCDE12345 --bundle com.you.PickupBox
#   ./scripts/setup.sh --dry-run                只看会改什么，不动文件
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT_FILE="PickupBox.xcodeproj/project.xcproj"
APP_ENTITLEMENTS="PickupBox/PickupBox.entitlements"
WIDGET_ENTITLEMENTS="PickupBoxWidgetsExtension.entitlements"
STORE_FILE="PickupBox/PickupStore.swift"
WIDGET_DATA_FILE="PickupBoxWidgets/PickupWidgetData.swift"

TEAM="${TEAM:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
GROUP_ID="${GROUP_ID:-}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
用法：
  ./scripts/setup.sh [选项]

选项：
  --team <ID>      开发者团队 ID（10 位），Xcode → Settings → Accounts 里可查
  --bundle <ID>    Bundle Identifier，例如 com.you.PickupBox
  --group <ID>     App Group，默认是 group.<Bundle ID>
  --dry-run        只打印将要修改的内容，不写入文件
  -h, --help       显示这段帮助
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --team)     TEAM="${2:-}"; shift 2 ;;
    --bundle)   BUNDLE_ID="${2:-}"; shift 2 ;;
    --group)    GROUP_ID="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "未知参数：$1"; usage; exit 1 ;;
  esac
done

for f in "$PROJECT_FILE" "$APP_ENTITLEMENTS" "$WIDGET_ENTITLEMENTS" "$STORE_FILE" "$WIDGET_DATA_FILE"; do
  if [ ! -f "$f" ]; then
    echo "✗ 找不到 $f"
    echo "  请在项目根目录执行：./scripts/setup.sh"
    exit 1
  fi
done

# ---------- 读取当前值 ----------
OLD_TEAM=$(grep -o '"DEVELOPMENT_TEAM": "[^"]*"' "$PROJECT_FILE" | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
OLD_BUNDLE_ID=$(
  grep -o '"PRODUCT_BUNDLE_IDENTIFIER": "[^"]*"' "$PROJECT_FILE" \
    | sed -E 's/.*"([^"]*)"$/\1/' \
    | sort -u \
    | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-
)
OLD_WIDGET_ID="${OLD_BUNDLE_ID}.PickupBoxWidgets"
OLD_GROUP_ID=$(grep -o 'group\.[A-Za-z0-9.-]*' "$APP_ENTITLEMENTS" | head -1)

# ---------- 交互式补全 ----------
if [ -z "$TEAM" ]; then
  echo "当前 Team ID：${OLD_TEAM:-（空）}"
  read -r -p "输入你的 Team ID（10 位，Xcode → Settings → Accounts 可查）： " TEAM
fi

if [ -z "$BUNDLE_ID" ]; then
  echo "当前 Bundle ID：$OLD_BUNDLE_ID"
  read -r -p "输入你的 Bundle ID [直接回车沿用当前的]： " BUNDLE_ID
  BUNDLE_ID="${BUNDLE_ID:-$OLD_BUNDLE_ID}"
fi

if [ -z "$GROUP_ID" ]; then
  GROUP_ID="group.$BUNDLE_ID"
fi

# ---------- 校验 ----------
fail() { echo "✗ $1"; exit 1; }

[[ "$TEAM" =~ ^[A-Za-z0-9]{10}$ ]] \
  || fail "Team ID 应该是 10 位字母数字，你输入的是：$TEAM"

[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] \
  || fail "Bundle ID 必须像 com.you.PickupBox 这样，至少两段，只能有字母数字和连字符"

[[ "$GROUP_ID" =~ ^group\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] \
  || fail "App Group 必须以 group. 开头，例如 group.com.you.PickupBox"

NEW_WIDGET_ID="${BUNDLE_ID}.PickupBoxWidgets"

# ---------- 汇报 ----------
echo
echo "将要做这些修改："
echo "  Team ID       ${OLD_TEAM:-（空）}  →  ${TEAM}"
echo "  Bundle ID     ${OLD_BUNDLE_ID}  →  ${BUNDLE_ID}"
echo "  Widget ID     ${OLD_WIDGET_ID}  →  ${NEW_WIDGET_ID}"
echo "  App Group     ${OLD_GROUP_ID:-（空）}  →  ${GROUP_ID}"
echo "  涉及文件       ${PROJECT_FILE}"
echo "                ${APP_ENTITLEMENTS}"
echo "                ${WIDGET_ENTITLEMENTS}"
echo "                ${STORE_FILE}"
echo "                ${WIDGET_DATA_FILE}"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  echo "（--dry-run：未写入任何文件）"
  exit 0
fi

read -r -p "确认执行？[y/N] " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES) ;;
  *) echo "已取消。"; exit 0 ;;
esac

# ---------- 备份 ----------
BACKUP=".setup-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP/PickupBox" "$BACKUP/PickupBoxWidgets" "$BACKUP/PickupBox.xcodeproj"
cp "$PROJECT_FILE" "$BACKUP/PickupBox.xcodeproj/" 2>/dev/null || true
cp "$APP_ENTITLEMENTS" "$BACKUP/" 2>/dev/null || true
cp "$WIDGET_ENTITLEMENTS" "$BACKUP/" 2>/dev/null || true
cp "$STORE_FILE" "$BACKUP/PickupBox/" 2>/dev/null || true
cp "$WIDGET_DATA_FILE" "$BACKUP/PickupBoxWidgets/" 2>/dev/null || true
echo "已备份到 $BACKUP"

# ---------- 替换 ----------
replace() { # $1 文件  $2 旧值  $3 新值
  OLD="$2" NEW="$3" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$1"
}

# 顺序很重要：先换 App Group（它的字符串里包含 Bundle ID），再换 Bundle ID
if [ -n "$OLD_GROUP_ID" ] && [ "$GROUP_ID" != "$OLD_GROUP_ID" ]; then
  replace "$APP_ENTITLEMENTS"    "$OLD_GROUP_ID" "$GROUP_ID"
  replace "$WIDGET_ENTITLEMENTS" "$OLD_GROUP_ID" "$GROUP_ID"
  replace "$STORE_FILE"          "$OLD_GROUP_ID" "$GROUP_ID"
  replace "$WIDGET_DATA_FILE"    "$OLD_GROUP_ID" "$GROUP_ID"
fi

if [ "$BUNDLE_ID" != "$OLD_BUNDLE_ID" ]; then
  replace "$PROJECT_FILE" "$OLD_WIDGET_ID" "$NEW_WIDGET_ID"
  replace "$PROJECT_FILE" "$OLD_BUNDLE_ID" "$BUNDLE_ID"
fi

if [ -n "$OLD_TEAM" ] && [ "$TEAM" != "$OLD_TEAM" ]; then
  replace "$PROJECT_FILE" "$OLD_TEAM" "$TEAM"
fi

# ---------- 校验结果 ----------
echo
echo "检查结果："

check_absent() { # $1 文件  $2 不该再出现的字符串  $3 描述
  if grep -qF "$2" "$1" 2>/dev/null; then
    echo "  ✗ $3：还残留 $2"
  else
    echo "  ✓ $3"
  fi
}

check_absent "$PROJECT_FILE" "$OLD_TEAM" "Team ID 已替换"
check_absent "$PROJECT_FILE" "$OLD_BUNDLE_ID" "Bundle ID 已替换"
check_absent "$APP_ENTITLEMENTS" "$OLD_GROUP_ID" "主 App 的 App Group 已替换"
check_absent "$WIDGET_ENTITLEMENTS" "$OLD_GROUP_ID" "小组件的 App Group 已替换"

APP_GROUP=$(sed -n 's:.*<string>\(group\.[^<]*\)</string>.*:\1:p' "$APP_ENTITLEMENTS" | head -1)
WIDGET_GROUP=$(sed -n 's:.*<string>\(group\.[^<]*\)</string>.*:\1:p' "$WIDGET_ENTITLEMENTS" | head -1)

if [ "$APP_GROUP" = "$GROUP_ID" ] && [ "$WIDGET_GROUP" = "$GROUP_ID" ]; then
  echo "  ✓ 两个 entitlements 都用 $GROUP_ID"
else
  echo "  ✗ entitlements 不一致：App=[$APP_GROUP] Widget=[$WIDGET_GROUP]"
fi

if [ "$(grep -cF "\"$GROUP_ID\"" "$STORE_FILE" 2>/dev/null || echo 0)" -ge 1 ] \
   && [ "$(grep -cF "\"$GROUP_ID\"" "$WIDGET_DATA_FILE" 2>/dev/null || echo 0)" -ge 1 ]; then
  echo "  ✓ 代码里的 appGroupID 与 entitlements 一致"
else
  echo "  ✗ 代码里的 appGroupID 没同步上"
fi

echo
echo "下一步："
echo "  1. 用 Xcode 打开 PickupBox.xcodeproj"
echo "  2. 两个 target 的 Signing & Capabilities 里确认 Team 已选中"
echo "  3. 如果 App Groups 报「组不存在」，点 + 手动创建 $GROUP_ID"
echo "  4. 选真机，⌘R"
echo
echo "出问题可以用 $BACKUP 里的文件还原。"
