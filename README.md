# operit-skill-code-review

Operit 技能「代码审查」的仓库。

给 AI 一套**带证据的代码审查流程**：十维度扫查、按改动类型触发的必查项、四级严重度、带 `file:line` 的 finding 输出，外加一个取证脚本 `scripts/sweep.sh`（环境探测 + 危险模式扫描）。

- 最后验证：2026-11-22（Operit Android 版）
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

为什么技能放在 `代码审查/` 子目录而不是仓库根上：这样两条安装路径（release 包解出来、内置导入 copy 出来的）都**只**包含技能本体，`README.md`、`install.sh`、`.gitignore` 不会被塞进技能目录。

## 许可

- 本仓库的 `SKILL.md`、`scripts/`、`references/android/`、`references/comments.md` 为原创，随本仓库分发。
- `references/upstream/` 来自上游开源代码审查技能，原许可与来源分别见 `references/upstream/LICENSE-code-review-skill.txt` 与 `references/upstream/SOURCE.txt`。
