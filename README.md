# operit-skill-code-review

Operit 技能「代码审查」的仓库。

给 AI 一套**带证据的代码审查流程**：十维度扫查、按改动类型触发的必查项、四级严重度、带 `file:line` 的 finding 输出，附两个脚本：`scripts/sweep.sh` 取证扫描（环境探测 + 危险模式扫描）、`scripts/make-release.sh` 打发布包（引用完整性断言）。

- 最后验证：2026-11-23（Operit Android 版）；具体版本与发布日期见 [Releases](https://github.com/LinZeroZero/operit-skill-code-review/releases)
- 依赖：无。`sweep.sh` 是 POSIX sh，toybox 与 GNU 环境都能跑；在 `/sdcard`（noexec）上用 `sh sweep.sh` 调用，不要 `./sweep.sh`。

## 安装

两种方式，装出来的结果一样：`<技能根>/代码审查/` 下有 `SKILL.md`、`scripts/`、`references/`。

### 方式一：release 包（推荐）

```sh
sh install.sh                       # 装到 /sdcard/Download/Operit/skills
sh install.sh /sdcard/tmp/skills    # 试装到别处，不动现有技能
sh install.sh --check               # 只看现状，不下载
sh install.sh --force               # 已存在时直接覆盖，不备份
```

退出码：`0` 成功 / `1` 用法 / `2` 缺 curl 或 tar / `3` 下载失败 / `4` 解包失败 / `5` 校验失败。

脚本会先用 `tar -tzf` 过一遍清单再解包（半截的包解出残缺目录却返回成功，这一步拦的就是它），已存在旧目录时改名成 `代码审查.bak.<时间戳>` 而不是删掉。

### 方式二：Operit 内置「从 GitHub 仓库导入」

| 填什么 | 值 |
|---|---|
| 仓库地址 | `https://github.com/LinZeroZero/operit-skill-code-review` |
| 或带子目录 | `https://github.com/LinZeroZero/operit-skill-code-review/tree/main/代码审查` |

两种都能装到 `代码审查`：导入器找不到根上的 `SKILL.md` 时会向下找唯一的那个，装出的目录名取 frontmatter 的 `name`。

> 同名技能已存在时，Operit 会拒绝导入（不覆盖）。升级请先删旧目录，或用方式一（它会自动备份）。

装完对 AI 说「用代码审查技能看这个改动」。

## 目录结构

```
代码审查/
├── SKILL.md                    流程、判定标准、输出格式
├── scripts/sweep.sh            取证扫描器（`sh sweep.sh --help` 看用法）
└── references/
    ├── android/                Android/KSU/apktool 这类工程的三篇补充
    ├── comments.md             注释审查判据（自研，与语言无关）
    └── upstream/               上游通用参考（按语言/领域分册，含 LICENSE 与 SOURCE.txt）
```

为什么技能放在 `代码审查/` 子目录而不是仓库根上：这样两条安装路径（release 包解出来、内置导入 copy 出来的）都**只**包含技能本体，`README.md`、`install.sh`、`.gitignore` 不会被塞进技能目录。仓库根的 `scripts/make-release.sh`（打发布包）同理，也不进技能目录。

## 发版

```sh
sh scripts/make-release.sh              # 默认打仓库内 代码审查/，输出 ${TMPDIR:-/tmp}/code-review.tar.gz
sh scripts/make-release.sh --check      # 引用完整性 + Release 正文状态（AUDIT=…），不打包
sh scripts/make-release.sh <技能目录> <输出路径>
```

退出码：`0` 成功 / `1` 用法 / `2` 目录不合规 / `3` 引用缺失 / `4` 打包失败 / `5` 包内校验失败 / `6` Release 正文缺 `## 审查` 节（或节内没有 PR 号）。

输出含 `COMMIT=`（出包源所在提交，非 git 目录为 `unknown`）与 `DIRTY=0/1`（**技能目录内**是否还有未提交改动 —— 只看 `代码审查/`，仓库根改了不影响包内容）。
`DIRTY=1` 时 `COMMIT` 只能说明「基于哪个提交」，不能说明「内容与它一致」—— 拿这种包去发版，资产就无法与标签对上。

**不要手工打包。** 手工 `tar` 最常出的错不是打失败，是「`SKILL.md` 引用了 `references/` 里某个文件，但那个文件没进包」—— 装完之后只在审查时 `read_file` 失败，报错点离病因很远。脚本从 `SKILL.md` 抓出全部 `references/*.md` 逐个核对，缺一个就拒绝出包；打完再解一遍清单反查，不信任 `tar` 的退出码。

**出包前先备好 Release 正文（规则 8 的第二道门）**：仓库根的 `RELEASE_NOTES.md` 必须有一节
`## 审查`，节内写明对应 PR 号与审查结论摘要 —— 缺了它、或节内没有 PR 号，脚本拒绝出包（退出码 6）；
`--check` 只报告 `AUDIT=ok/missing`，不拦截。这份文件同时就是发版正文：建 Release 时把它贴进正文，
别再手写一份造成两处不同步。

资产名必须是 `code-review.tar.gz` —— `install.sh` 取的是 `releases/latest/download/code-review.tar.gz`。

digest 环境绑定：资产用 GNU tar（proot 内）构建，`SHA256` 只用于验证**同一环境**的重建；
toybox tar（Android 本体）打的包内容相同、字节不同 —— 跨环境 digest 对不上是预期行为，
别拿它当损坏信号。


## 许可

- 本仓库的 `SKILL.md`、`scripts/`、`references/android/`、`references/comments.md` 为原创，随本仓库分发。
- `references/upstream/` 来自上游开源代码审查技能，原许可与来源分别见 `references/upstream/LICENSE-code-review-skill.txt` 与 `references/upstream/SOURCE.txt`。
