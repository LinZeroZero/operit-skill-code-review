#!/bin/sh
# 代码审查 · 取证扫描器（POSIX sh，toybox 兼容）
#
# 为什么是脚本而不是正文里的五行 grep：
#   1) 正则最容易抄错 —— 第 2 条改过一次才准（旧写法在 starrail_sched 上给 5 条、
#      其中 4 条是已加引号的安全代码；新写法给 2 条、都是真的没加引号）。
#      抽成脚本后改一次全体生效，跨会话/跨模型输出可比。
#   2) 能加防护 —— 命中行数默认截断到 200 行，避免 grep -r 在仓库里刷出几千行撑爆上下文。
#
# 用法:
#   sh sweep.sh                         # 扫当前目录的 *.sh
#   sh sweep.sh path/to/module          # 扫指定目录（可给多个，含空格也能正确处理）
#   sh sweep.sh --include '*.js' src/   # 换文件类型
#   sh sweep.sh --max-hits 50 .         # 每个模式最多打印 50 行（默认 200）
#   sh sweep.sh --no-env .              # 跳过环境探测，只跑模式（此时没有 == env == 段）
#
# 选项必须写在路径之前；以 - 开头的路径用 `--` 分隔，例如: sh sweep.sh -- --weird-dir
#
# 命中不等于有 bug —— 这些正则只圈候选，判断靠自己看一眼。
# 依赖: find / grep -E / awk / wc / head / mktemp（toybox 均有）。
# 注意: /sdcard 是 noexec，只能用 `sh <path>` 调用，chmod +x 后直接执行会 Permission denied。

set -u

INCLUDE='*.sh'
MAX_HITS=200
DO_ENV=1
USED_DD=0

# 用法正文取自本文件头部的注释块，不写死行号 —— 头部增删行时不会漏出代码行。
usage() {
  awk 'NR > 1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print; next } exit }' "$0"
}

die() {
  printf '%s\n' "$1" >&2
  exit 2
}

# 选项在前、路径在后。路径留在位置参数里，不拼成一个字符串 ——
# 拼字符串再靠不加引号去拆，会把「含空格的路径」拆成两段、静默扫到 0 个文件。
while [ $# -gt 0 ]; do
  case "$1" in
    --include)
      [ $# -ge 2 ] || die '--include needs a value'
      INCLUDE=$2; shift 2 ;;
    --max-hits)
      [ $# -ge 2 ] || die '--max-hits needs a value'
      MAX_HITS=$2; shift 2 ;;
    --no-env) DO_ENV=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --) USED_DD=1; shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[ $# -gt 0 ] || set -- .
case "$MAX_HITS" in ''|*[!0-9]*) die '--max-hits must be a number' ;; esac

# toybox 的 find 不认 `--`，会把 `-` 开头的路径当选项（find: bad arg '-type'）。
# 所以只在用户显式用了 `--` 之后，把 `-` 开头的路径统一加 `./` 前缀，find 才认得出这是路径。
# 用「先 shift 再 append」轮转 n 次改写位置参数 —— POSIX sh 没有数组。
if [ "$USED_DD" = 1 ]; then
  n=$#
  i=0
  while [ "$i" -lt "$n" ]; do
    p=$1; shift
    case "$p" in
      -*) p="./$p" ;;
    esac
    set -- "$@" "$p"
    i=$((i + 1))
  done
fi

# 路径不存在就直接失败：否则 find 输出 0 个文件，与「目录里真的没有匹配文件」无法区分。
for p in "$@"; do
  if [ ! -e "$p" ]; then
    case "$p" in
      ./-*)
        if [ "$USED_DD" = 1 ]; then
          die "path not found: $p (input was ${p#./}; './' prefix added because find rejects '-'-leading paths)"
        fi ;;
      -*)
        if [ "$USED_DD" = 0 ]; then
          die "path not found: $p (options must come before paths; use -- to separate)"
        fi ;;
    esac
    die "path not found: $p"
  fi
done

# 临时目录：优先 mktemp 默认（$TMPDIR），其次 /data/local/tmp、/tmp；都不行就报错退出，
# 不静默降级到某个写死路径（写死路径可能在别的设备上不可写）。
TMP=$(mktemp -d 2>/dev/null) || TMP=''
if [ -z "$TMP" ]; then
  for base in "${TMPDIR:-}" /data/local/tmp /tmp; do
    if [ -n "$base" ] && [ -d "$base" ]; then
      TMP=$(mktemp -d "$base/sweep.XXXXXX" 2>/dev/null) && break
      TMP=''
    fi
  done
fi
if [ -z "$TMP" ]; then
  printf 'cannot create temp dir (tried TMPDIR, /data/local/tmp, /tmp)\n' >&2
  exit 1
fi

# cleanup 会被调用两次（信号 trap 一次、EXIT trap 一次）：第二次 find -delete 在已删目录上返回 1，
# 而 mksh 会用 EXIT trap 的末命令状态覆盖 exit N —— 信号 trap 必须先 trap - EXIT 再退出，
# 否则被中断时退出码会变成 1，调用方分不清「被中断」和「出错」。
cleanup() { find "$TMP" -depth -delete >/dev/null 2>&1; }
trap cleanup EXIT
# 退出码 = 128+信号编号（INT 130 / HUP 129 / TERM 143）。
# 实测（用 --no-env /system 让脚本活过 0.5 秒再发信号）：INT → 130、TERM → 143，无临时目录残留。
# 扫小目录时脚本 1 秒内就跑完，发信号来不及，测不到这条路径。
# HUP 在本机入口即被忽略（SigIgn bit0），挂上不触发；保留是为了在别的环境兜住临时目录。
trap 'trap - EXIT; cleanup; exit 130' INT
trap 'trap - EXIT; cleanup; exit 129' HUP
trap 'trap - EXIT; cleanup; exit 143' TERM

# ---- 一、环境探测：这些命令真的存在吗（别假设 toybox 有 seq / flock / stat -c）
if [ "$DO_ENV" = 1 ]; then
  printf '== env ==\n'
  for c in flock setsid nohup pgrep timeout seq stat readlink; do
    printf '%s: %s\n' "$c" "$(command -v "$c" 2>/dev/null || echo MISSING)"
  done

  printf '\n== toolchain ==\n'
  seen=0
  for b in /system/bin/toybox /system/bin/busybox; do
    if [ -e "$b" ]; then ls -l "$b"; seen=1; fi
  done
  [ "$seen" = 1 ] || printf 'toybox/busybox: not found under /system/bin\n'
  toybox 2>/dev/null | head -3
fi

# ---- 二、危险模式扫描
# 逐路径 find：每个路径单独传给 find，含空格也不会被拆开。
list_files() {
  for p in "$@"; do
    find "$p" -type f -name "$INCLUDE" -print 2>/dev/null
  done
}

list_files "$@" > "$TMP/files"
NFILES=$(wc -l < "$TMP/files" | tr -d ' ')

printf '\n== patterns ==\ninclude: %s\npaths:  %s\nfiles:  %s\n' "$INCLUDE" "$*" "$NFILES"
if [ "$NFILES" -eq 0 ]; then
  printf '(no files match --include %s)\n' "$INCLUDE"
  exit 0
fi

# scan <标签> <扩展正则> <路径...>
# 用 `find -exec grep /dev/null {} +`：/dev/null 占位强制 grep 走「多文件」模式，
# 否则单文件命中时输出只有 `行号:内容`、看不出是哪个文件。
scan() {
  label=$1
  pat=$2
  shift 2
  printf '\n-- %s\n' "$label"
  for p in "$@"; do
    find "$p" -type f -name "$INCLUDE" -exec grep -nE "$pat" /dev/null {} + 2>/dev/null
  done > "$TMP/out"
  n=$(wc -l < "$TMP/out" | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    printf '(no hits)\n'
    return 0
  fi
  head -n "$MAX_HITS" "$TMP/out"
  if [ "$n" -gt "$MAX_HITS" ]; then
    printf '... truncated (%s hits total, showing %s; raise --max-hits to see more)\n' "$n" "$MAX_HITS"
  fi
}

scan '后台且无 setsid（进程可能随父 shell 退出被杀）' \
     '(^|[^\\])>[[:space:]]*/dev/null[[:space:]]*2>&1[[:space:]]*&' "$@"

scan '变量独立成词、未加引号（"$X/y" 不算，cmd $tid 才算）' \
     '(^|[[:space:]=(])\$[A-Za-z_][A-Za-z0-9_]*([[:space:]]|$)' "$@"

scan '删除路径含变量 / find -delete（不可逆操作）' \
     'rm[[:space:]]+[^;#]*\$|find[[:space:]]+[^;#]*-delete' "$@"

scan '可省掉的 fork（echo|tr、cat|sed 这类）' \
     '(cat|echo|printf)[[:space:]]+.*\|[[:space:]]*(tr|sed|awk)' "$@"

scan '常驻循环（确认轮询频率与退出条件）' \
     'while[[:space:]]+true|while[[:space:]]+:;' "$@"

printf '\n== done ==\n'
