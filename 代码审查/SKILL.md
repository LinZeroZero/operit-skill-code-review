---
name: 代码审查
description: 审查代码改动或整份文件，输出带 file:line 的 finding
---

最后验证: 2026-11
依赖版本: 无外部依赖（纯规则档，工具探测到才增强）

# 代码审查

目标：把「看起来不对」变成**能被反驳的具体断言**——每条 finding 都有位置、有依据、有改法。

## 0. 四条可移植性原则

1. **零网络依赖**：所有规则档随技能目录分发，断网可用。
2. **零包硬依赖**：不假设装了某个包或工具。工具（`shellcheck`、`python3`、`git`）探测到就增强，探测不到就不提。
3. **零设备假设**：不写机型、核心编号、本机独有的工具链路径。凡涉及系统行为，先实测（`command -v` / `ls` / `--help`）再判定。
4. **路径自定位**：`<SKILL_DIR>` = 本 SKILL.md 所在目录，Operit 默认 `/sdcard/Download/Operit/skills/代码审查/`；`<SKILL_DIR_UI>` = 「UI审查」技能目录，默认 `/sdcard/Download/Operit/skills/UI审查/`。换设备只需替换这两个前缀。

## 1. 开工前十秒

先问清三件事，缺一项就会把审查做成读后感：

| 要确认 | 为什么 | 不知道时怎么办 |
|---|---|---|
| 审查范围 | 「刚刚的改动」和「这个文件」是两种工作量；diff 超过约 400 行，结论会失真 | 先要 diff；拿不到就按文件审，并在报告里写明范围 |
| 代码要做什么 | 没有意图就没有「bug」，只有风格偏好 | 让用户一句话说清预期行为 |
| 运行环境 | shell 要区分 mksh/bash/busybox；前端要区分浏览器/WebView | 读 shebang、读构建配置，别猜 |

## 2. 四阶段

**阶段 1 · 上下文**：范围、意图、语言与运行时、有无测试。
**阶段 2 · 整体**：方案是否解决对的问题；模块边界；性能量级；错误处理策略；可测性。大改动读 `references/upstream/architecture-review-guide.md`。
**阶段 3 · 逐行**：逻辑与边界、安全、可维护、**复用审计**（这段是不是重复实现了已有的东西）。
**阶段 4 · 结论**：先结论后依据；给严重度分布；明确「能不能合」。

阶段 2 允许扫读（看结构、看方案是否解决对的问题），阶段 3 必须逐行；两者都不许跳过——只做逐行会漏掉「实现得很干净的错方案」。

## 2.4 审查维度（该从哪些角度想）

对应 Google eng-practices 的十项审查维度。这是**扫查顺序**，不是打勾项：每项都过一遍，没发现问题就不写 finding；但**不许跳读**（见最后一项）。

| 维度 | 问什么 | 本项目对应 |
|---|---|---|
| Design | 这段改动该不该存在？该放这里还是库/别的模块？与系统其余部分集成得好吗？ | 方案是否解决对的问题；是否重复实现了已有能力（阶段 3 复用审计） |
| Functionality | 作者想做的事，代码真做到了吗？边界、并发、用户视角有无坑？ | 并发按 §2.5 必查；UI 改动按 §2.7 触发项 |
| Complexity | 行/函数/类是否「读一遍看不懂」？是否为不需要的将来留了抽象？ | 过度设计、投机性抽象要点出 |
| Tests | 有没有测试？失败路径测了吗？ | 本项目多为反编译/改包/模块脚本类工程，无单测 → 按 §2.6 用可执行证据替代 |
| Naming | 名字是否准确表达含义？ | 偏好类命名交 linter；**语义误导**（会让人用错）属于可维护性问题，可提 |
| Comments | 注释是否解释**为什么**，而不是复述代码在做什么？ | 本项目要求注释解释 why、写清运行时状态文件格式与关键约定 |
| Style | 格式、缩进、行宽、命名偏好 | **不评**，见 §7「明确不做」 |
| Consistency | 与代码库既有写法一致吗？同一抽象的多实现是否同口径？ | 后者按 §2.7 的 provider 触发项 |
| Documentation | 改了行为却没说？README / CHANGELOG / 注释是否需同步？ | 对外行为变化时必须提 |
| Every Line | **逐行读，不跳读** | 与阶段 3 一致；跳读会漏掉「实现得很干净的错方案」 |

依据：https://google.github.io/eng-practices/review/reviewer/looking-for.html
（该页开头要求结合 The Standard of Code Review 使用：追求持续改善，不追求完美，不重要的问题标 `Nit:`。）

**近似判据检查**：当逻辑用「类型 / 名字 / 枚举 / 来源」去近似「实际行为」时（例：按 provider 类型推断「这个数是不是服务端给的」），必须举出至少一个**会误判的具体情形**。举不出来，说明这条判断没有被验证，只是措辞。

常见形态：用 `type` 近似 `semantics`、用 `name` 近似 `capability`、用「由谁调用」近似「值从哪来」。举出反例后判断仍成立，就在 finding 里写明它；一举反例即失效的，降级为假设，进「存疑」列（见 §3）。

实测（2026-11，Operit PR #1519）：判据写成「provider 类型是 GOOGLE / GEMINI_GENERIC 才显示真实值」，两个方向都错——本地推理（MNN / llama.cpp）用本地 `countTokens()` 走同一条上报通道却被当成真值；`OpenCodeProvider.kt` 里的 `OpenCodeGeminiProvider : GeminiProvider` 配置类型是 `OPENCODE`，真实上报反被藏掉。

## 2.5 必查项：并发与共享状态

Google 工程实践明确：并发问题**几乎无法靠「跑一下没崩」发现**，必须人想。所以这一条是**必查**，不是可选：

1. 列出本次改动**新增或复用**的所有共享可变状态：C 的 `static` 变量、Java 的 `static` 字段与单例、复用中的 fd 与连接、缓存、全局 flag；
2. 对每一处回答：谁写、谁读、能否并发、最坏的交错是什么；
3. 若判断「暂时不会并发」，把它写进**存疑**列（例如「依赖调用方单线程」），不要当成已证明安全。

实例：C 采样器用文件级 `static int g_fd / g_seq` 保存常驻 socket —— 按此条列出「`Bridge.pingWarm` 若被两线程调用会互收对方的回复」，据此加了非阻塞单飞锁。

## 2.6 验证口径：没有可执行证据不算验证

Google 要求「测试与产品代码在**同一个 CL**」。反编译、改包、模块脚本这类工程没有单测，替代物是**可执行证据**：

- 「验证」一栏必须写清 **跑了什么命令 → 看到什么输出**，不能只写「测试通过」「功能正常」；
- 证据要能区分「改了」与「没改」：计数、日志行、进程数、`cutime`、sha256、版本号回读；
- **只在成功路径上跑过，不算验证**：失败路径（超时、断网、so 加载失败、版本号 sed 未命中）要单独给出观察结果；
- 能自动化就自动化，但**装机观测同样算证据**（`dumpsys`/`ps`/`logcat` 的输出贴进报告）。

实例：mod-13 的验证写的是「20 次采样中 `ping` 子进程 0、`cutime/cstime` 均 +0、`time=178 ms` 整数」，而不是「零 fork 生效」。

- **低频采样会漏掉短命现象**：判断「有没有 fork / 有没有起进程」时，1 秒一次的 `ps` 抓不到只活几十毫秒的进程，
  会得到**假阴性**（实测踩过：mod-13 因为采样间隔 1 秒，把「一直在 fork」误报成「零 fork」）。
  要么提高采样频率，要么改用**累计指标**（`/proc/<pid>/stat` 的 `cutime/cstime`），并且先确认「功能确实在跑」。

## 2.7 改动类型触发项

**触发式，不是打勾式**：改到下面这类东西，就必须去看对应那几处；看过后没发现问题，不要求为它写一条 finding。目的是防「靠印象以为查全了」——例如只补了 zh/en 两份 `strings.xml`，漏掉同样含该 key 的 `values-pt-rBR`。

| 改动涉及 | 必查 |
|---|---|
| Android 资源 / i18n | `res/xml/locales_config.xml` 全量比对；所有含该 key 的 `values-*/strings.xml`，用 `grep -rl 'name="<key>"'` 列全，不靠印象 |
| provider / 适配器抽象 | 所有实现类是否同口径：同一回调在不同实现里的**调用时机**（请求前 / 响应后）、单位、是否含缓存值 |
| UI 显示值来源 | 该值的写入时机、清空时机、跨会话 / 重启的持久性；与同一界面上既有同类值是否同源 |
| 计费 / 配额 / 限额 | 计费单位（次 / token / 金额）、缓存折扣、时区与重置点 |
| 持久化结构变更 | 迁移路径、旧数据兼容、回滚方式 |

依据：Google eng-practices 的审查维度（Design / Functionality / Complexity / Tests / Naming / Comments / Style / Consistency / Documentation / Every Line）是「该从哪些角度想」，并明确 "There is no such thing as 'perfect' code"，不要求逐项通过；Kubernetes 的 PR 模板是结构化声明而非打勾清单。故本表写成触发式。

## 3. 严重度与 finding 格式

| 级别 | 含义 | 处理 |
|---|---|---|
| 🔴 blocking | 会出错、会丢数据、会破坏可还原性、安全漏洞 | 必须改 |
| 🟡 important | 会误导后来人、埋雷、或不符约定 | 应该改 |
| 🟢 nit | 偏好问题 | 可以不改 |
| 💡 / 📚 / 🎉 | 建议 / 讲解 / 表扬 | 不阻断，只标注 |

每条 finding 固定七列，缺列就是意见不是结论：

```
| # | 严重度 | 位置 | 问题 | 依据 | 建议 | 存疑 |
```

- **位置**：`file:line`；跨文件就写主责文件 + 关联点。
- **依据**：必须是可指认的东西——`references/android/shell-magisk.md#备份只写一次`、`references/upstream/c.md#Always carry size with buffers`、某条命令的实测输出。写不出依据就降级到「存疑」。
- **建议**：给出方向即可，不要替用户重写整个文件（见 §7）。
- **存疑**：`未实测` / `依赖具体内核` / `需在目标机确认`。**这一列是本技能的信誉来源**：把推测混进结论，一次就够让整份报告作废。

## 4. 路由表

按**文件类型**选档，不按项目语言选。多类型混合就分节审。

| 看到什么 | 读哪份 |
|---|---|
| `*.sh`、模块目录、`post-fs-data.sh`、`service.sh` | `references/android/shell-magisk.md`（**优先于任何上游档**） |
| KernelSU/APatch WebUI、单文件 HTML、`ksu.exec` | `references/android/ksu-webui.md` |
| `smali/**`、`res/**`、`AndroidManifest.xml` | `references/android/smali-apk.md` |
| 其他语言 | `references/upstream/<lang>.md`：`c` `cpp` `csharp` `go` `java` `java8` `kotlin` `python` `php` `ruby` `rust` `swift` `dart` `typescript` `zig` `qt`；前端 `react` `vue` `angular` `svelte` `css-less-sass`；后端 `django` `fastapi` `nestjs` |
| 跨领域 | `references/upstream/cross-cutting/`：`sql-injection-prevention` `xss-prevention` `n-plus-one-queries` `error-handling-principles` `async-concurrency-patterns` |
| 通用质量 | `references/upstream/code-quality-universal.md`、`references/upstream/common-bugs-checklist.md`、`references/upstream/security-review-guide.md`、`references/upstream/performance-review-guide.md` |
| 反馈怎么说 | `references/upstream/code-review-best-practices.md` |

上游档是英文原文，按小节标题（`##`）取用；引用时写清小节名，方便对方回查。

## 5. 取证：先跑命令，再下判断

静态审查最容易犯的错是「凭印象断言工具行为」。一条命令拿硬事实：

```sh
sh <SKILL_DIR>/scripts/sweep.sh <目录>              # 默认只扫 *.sh；--include '*.js' 换类型
sh <SKILL_DIR>/scripts/sweep.sh --max-hits 50 .     # 每模式最多 50 行（默认 200）
```

默认输出三段：`== env ==`（8 个外部命令是否存在，别假设 toybox 都有）、`== toolchain ==`（toybox/busybox 位置与 applet）、`== patterns ==`（5 条危险模式 + 命中数，超限截断）；加 `--no-env` 时只剩 `== patterns ==`。`/sdcard` 是 noexec，只能 `sh <path>` 调用。

### 5.1 五条模式与判断要点

| 模式 | 判断要点 |
|---|---|
| `> /dev/null 2>&1 &` 且无 `setsid` | 父 shell 退出后它该不该继续活 |
| 变量独立成词、未加引号 | `"$X/y"` 不算；`cmd $tid` 才算 |
| `rm … $VAR` / `find … -delete` | 变量为空时会删到哪 |
| `cat`/`echo`/`printf` 后接 `\| tr`/`sed`/`awk` | 只写 `cat` 会漏 `$(echo "$f" \| tr '/' '_')` |
| `while true` / `while :;` | 轮询频率与退出条件 |

第 2 条实测：`starrail_sched` 上旧写法给 5 条（其中 4 条是已加引号的安全代码），新写法给 2 条、都是真的没加引号。**这就是抽成脚本的理由**——正则改一次全体生效，不靠记忆重抄。

**命中不等于有 bug**：注释行、字符串字面量里的同形文本也会命中，先看行首。

### 5.2 前端数值不要目测

对比度、字号档、间距档不要目测，也不要在脑子里算：

```sh
node -e "const a=require('<SKILL_DIR_UI>/scripts/audit.js'); console.log(a.auditContrast('#9aa0c0','#0f1220'))"
```

输出 7.24 就是实测值；> 4.5 正文达标，> 3 大字（>=24px 或 >=18.66px 且 700）达标。

不要在本技能里重写一份对比度公式——两份实现迟早会算出两个数，那时就没有可信的一方了。

## 6. 三档怎么用

- `references/android/shell-magisk.md`：模块生命周期与时机、外部命令可用性、fork 与单例、备份/还原对称性、sysfs 写失败静默、noexec 约束。审 Magisk/KernelSU/APatch 模块脚本时**先读这份**。
- `references/android/ksu-webui.md`：`ksu.exec` 返回值形态、错误分支、执行成功不等于命令成功、DOM 取值方式、视口与缩放。
- `references/android/smali-apk.md`：寄存器宽度与 `/range`、`const/4` 边界、资源 ID 连带、manifest 运行时副作用、R8 混淆后的定位方式。

## 7. 明确不做

- **不改代码**。审查的产物是判断，不是补丁；要改另开任务，避免「边审边改」导致结论失去独立性。
- **不评格式**：缩进、行宽、命名偏好交给 linter 与 formatter。
- **不猜设备行为**：未经实测的 sysfs/内核/固件行为一律进「存疑」列。
- **不把上游档当本地规范**：上游是通用最佳实践，与项目既有约定冲突时，以项目约定为准，并指出冲突点。

## 8. 常见借口（自查用）

| 想法 | 事实 |
|---|---|
| 「这改动很小，不用审」 | 小改动同样能改坏备份路径、删除路径、权限。范围小 ≠ 风险小 |
| 「我边改边审更快」 | 改的人看不见自己的假设。要改就改完再另起一轮审 |
| 「改完我又从头读了一遍」 | 读的时候脑子会按「我想写什么」补全。要用外部输入跑一遍，见 §9 |
| 「跑起来没问题就是对的」 | 只在成功路径上跑过，说明失败路径从没被测过 |
| 「这段照着某项目抄的」 | 抄来的东西最容易被当成正确，也最容易缺上下文 |
| 「用户只问了 X，其他不归我管」 | 🔴 级问题一律越界上报，其余可以一句话带过 |

## 9. 审自己的改动

改完再读自己的代码，是整条流程里最不可靠的一步：脑子里留着「我想写什么」，读的时候会自动按那个样子补全。四个成本很低的手段，按性价比排：

| 手段 | 怎么做 | 实测抓到过 |
|---|---|---|
| **当外部输入执行** | 用脚本从**文件里原样提取**那段代码（不是凭记忆重打），套一个最小 harness 跑 | 注释声称「随机回调名防连点覆盖」，实测连点后旧结果盖掉新结果 |
| **边界四连** | 空输入 / 失败或非零退出码 / 并发两次 / 回调或事件丢失 | 回调不来时界面永久停在「执行中...」，且没有超时 |
| **跨节一致性** | 改了 A 处的结论，全文 `grep` 旧说法是否还在 | 这处已论证 `r` 是字符串，那处却还在用 `r.stderr` |
| **结构自检** | 代码块围栏为偶数、列表缩进不断裂、禁词门禁 | — |

报告里要分开写「原文本来就是错的」和「我这轮改错的」——后者更常见，也更难被自己发现。

一句总结：**读一遍不算验证；有 harness 能跑的，就跑。**

### 第二双眼睛（比自审可靠）

自审的根本缺陷是「作者与评审者是同一个脑子」。成本最低的补救：把**待审 diff 原文**交给一个**不共享上下文**的 agent / 新对话，只给它规则与位置、不给你的结论，然后两边取并集。

它最可能驳回的，恰恰是你确信「这里肯定没问题」的地方 —— 那正是你最需要被质疑的地方。

## 10. 目录与许可

上游底稿：`awesome-skills/code-review-skill`（MIT，提交号与更新方法见 `references/upstream/SOURCE.txt`）。`references/upstream/` 30 篇（24 篇语言/前端/后端档 + 6 篇通用档）+ 5 篇跨领域（英文原文）；`references/android/` 自研三档（中文）。目录树由宿主注入，不重复。

## 11. 使用前自检

**覆盖**：shell/Magisk、KSU WebUI、smali 三档与 20+ 语言；四阶段流程、十项审查维度（§2.4）、改动类型触发项（§2.7）、严重度分级、带 file:line 的 finding。

**不覆盖**：运行时性能剖析、模糊测试、整体架构评审、加固包逆向（交「APK逆向改包」技能）。

**开工前复核**：每条 finding 必须有 file:line；有 harness 能跑就跑；读一遍不算验证。
三档为自研，只写判定方法、不写具体机型结论——换设备不失真。