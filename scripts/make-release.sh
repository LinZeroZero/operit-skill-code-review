#!/system/bin/sh
# 一句话：把「代码审查」打成 release 资产，并在打包前后各做一次文件完整性断言。
#
# 为什么需要它（取舍写在前面，改之前先读）：
#   1. 仓库没有 .github/workflows，code-review.tar.gz 全靠手工做。手工打包最常出的错不是
#      打失败，是「SKILL.md 引用了某个 references 文件，但那个文件没进包」——装完只在
#      审查时 read_file 失败，报错点离病因很远（引用在 §2.7，文件缺失在安装目录）。
#      所以断言来源取 SKILL.md 本身：把里面出现的 references/*.md 全抓出来，缺一个就拒绝出包。
#   2. 打包后重新解一遍清单反查，不信任 tar 的退出码 —— 半截包也会返回 0。
#   3. 只依赖 toybox 的 tar / grep / sed / sha256sum（Android /system/bin 都有，不需要 apt）。
#   4. 打的是技能目录，不是仓库根：包顶层必须是中文技能名，装完得到 skills/代码审查/SKILL.md。
#      本脚本自己在 scripts/ 下，不属于技能产物，不会被装进包。
#
# 用法:
#   sh make-release.sh                          # 打默认技能目录到 ./code-review.tar.gz
#   sh make-release.sh /sdcard/x/代码审查       # 指定技能目录
#   sh make-release.sh <dir> /root/out.tar.gz   # 指定输出路径
#   sh make-release.sh --check                  # 只做引用完整性检查，不打包
#
# 输出（每行 KEY=VALUE，便于脚本消费）:
#   STATUS / DIR / ASSET / SIZE / SHA256 / FILES / REFS
#
# 退出码: 0 成功 / 1 用法 / 2 目录不合规 / 3 引用缺失 / 4 打包失败 / 5 包内校验失败

set -u
NAME="代码审查"
SKILL_DIR=""
OUT=""
CHECK_ONLY=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit "$2"; }

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -*)      die "未知选项: $arg" 1 ;;
    *)       if [ -z "$SKILL_DIR" ]; then
               SKILL_DIR=$arg
             elif [ -z "$OUT" ]; then
               OUT=$arg
             else
               die "多余参数: $arg" 1
             fi ;;
  esac
done

[ -n "$SKILL_DIR" ] || SKILL_DIR="/sdcard/Download/Operit/skills/$NAME"
[ -n "$OUT" ] || OUT="$PWD/code-review.tar.gz"

# ---- 1. 目录合规 ----
[ -d "$SKILL_DIR" ] || die "技能目录不存在: $SKILL_DIR" 2
[ -f "$SKILL_DIR/SKILL.md" ] || die "技能目录里没有 SKILL.md: $SKILL_DIR" 2
BASE=$(basename "$SKILL_DIR")

# ---- 2. 引用完整性：断言来源就是 SKILL.md 自己 ----
# 只取 references/ 下的 .md；`#anchor` 不会被这个正则带走。
REFS=$(grep -o 'references/[A-Za-z0-9_./-]*\.md' "$SKILL_DIR/SKILL.md" 2>/dev/null | sort -u)
if [ -z "$REFS" ]; then
  printf 'NOTE: SKILL.md 里没有 references/*.md 引用，跳过引用校验\n' >&2
  REF_CNT=0
else
  REF_CNT=$(printf '%s\n' "$REFS" | grep -c .)
fi

miss=0
for r in $REFS; do
  if [ ! -f "$SKILL_DIR/$r" ]; then
    printf 'MISSING: %s（SKILL.md 引用了它，但文件不存在）\n' "$r" >&2
    miss=$((miss + 1))
  fi
done
[ "$miss" -eq 0 ] || die "有 $miss 个被引用的文件缺失，拒绝出包" 3

if [ "$CHECK_ONLY" -eq 1 ]; then
  printf 'STATUS=check-ok\n'
  printf 'DIR=%s\n' "$SKILL_DIR"
  printf 'REFS=%s\n' "$REF_CNT"
  exit 0
fi

# ---- 3. 打包 ----
# 从父目录打包，保证包顶层是中文技能名；.git 与编辑备份不入包。
PARENT=$(dirname "$SKILL_DIR")
rm -f "$OUT" 2>/dev/null
(cd "$PARENT" && tar -czf "$OUT" --exclude="$BASE/.git" --exclude='*.bak' "$BASE") \
  || die "打包失败: $OUT" 4

# ---- 4. 包内反查：不信退出码，重新解一遍清单 ----
LIST=$(tar -tzf "$OUT" 2>/dev/null) || die "包不可读（tar -tzf 失败）: $OUT" 5

printf '%s\n' "$LIST" | grep -q "^$BASE/SKILL.md$" \
  || die "包内缺 $BASE/SKILL.md" 5

for r in $REFS; do
  printf '%s\n' "$LIST" | grep -q "^$BASE/$r$" \
    || die "包内缺被引用的文件: $r" 5
done

if printf '%s\n' "$LIST" | grep -q '\.git/'; then
  die "包内含 .git（--exclude 没生效？）: $OUT" 5
fi

# ---- 5. 输出 ----
NFILES=$(printf '%s\n' "$LIST" | grep -vc '/$')
SIZE=$(ls -l "$OUT" 2>/dev/null | awk '{print $5}')
SUM=$(sha256sum "$OUT" 2>/dev/null | awk '{print $1}')

printf 'STATUS=ok\n'
printf 'DIR=%s\n' "$SKILL_DIR"
printf 'ASSET=%s\n' "$OUT"
printf 'SIZE=%s\n' "${SIZE:-unknown}"
printf 'SHA256=%s\n' "${SUM:-unknown}"
printf 'FILES=%s\n' "${NFILES:-unknown}"
printf 'REFS=%s\n' "$REF_CNT"