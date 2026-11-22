# APK 反编译工程（smali / 资源 / manifest）

审反编译产物、或审「改完不生效」的补丁时读这份。核心问题不是代码风格，而是**这个改动会不会被真正执行**。

## 1. 先判层，再谈对错

同一件事往往有四层可改，深度与风险完全不同。审查时先问「他改的是哪一层，这一层在运行时生效吗」：

| 层 | 载体 | 生效条件 | 典型失效点 |
|---|---|---|---|
| 值/开关 | `shared_prefs`、配置文件 | 应用启动时读取；已装机上直接改文件即可，**不动签名** | 应用在别处缓存了默认值，或改的是服务端下发的配置 |
| 资源 | `res/`、`resources.arsc` | 重新打包后生效 | 改错语言包、字符串被别的 locale 覆盖、ID 变了引用没跟着变 |
| 代码 | `smali/**` | 重新打包 + 签名 + 安装 | 字节码约束不满足，编译通过但运行崩溃 |
| manifest | `AndroidManifest.xml` | 安装时确定 | 运行时被代码用 `metaData` 动态覆盖；签名/权限变更导致校验失败 |

判据：**如果改动是由服务端下发或运行时计算的，改本地任何一层都不会生效**。这类判断必须真的去看网络响应或读代码，不能凭名字猜（比如「广告开关」常常来自远端配置）。

## 2. smali 的硬约束

一个反直觉的事实：**`apktool b` 成功不代表寄存器与控制流是对的**。smali 只查语法与格式，不跑数据流校验。下面按「编译器拦不拦」分组——这决定你该信工具还是信自己。

### 2.1 编译期会拦住（报错原文可直接搜）

- **35c 最多 5 个寄存器**。6 个报 `A list of registers can only have a maximum of 5 registers. Use the <op>/range alternate opcode instead.` → 改 `invoke-direct/range {v0 .. v5}, ...`，或先 `move` 到连续寄存器。
- **`const/4` 只有 -8..7**。`const/4 v0, 0x8` 报 `Invalid literal value: 8. Must be between -8 and 7, inclusive.`
- **`.registers` 与 `.locals` 不能同写**。报 `There can only be a single .registers or .locals directive in a method`。
- **`catch` 指向不存在的标签**。报 `Cannot get the location of a label that hasn't been placed yet.`

### 2.2 编译期一律放过（工具不帮你，必须人工或装机验）

下面三种写法实测（apktool 3.0.1）全部 `rc=0`：

- **`const/16` 越界不报错，静默截断**。`const/16 v0, 0x8000` 能编过，反编译出来是 `return -32768`。这比 `const/4` 危险：`const/4` 越界会拦住，`const/16` 不会。要 32 位常量（含资源 ID 全值）用 `const`，别用 `const/16`。
  顺带一个巧合：资源 ID 高字是 `0x7f`，而 `0x7fff` 正好是 16 位有符号上限，所以 `const/16 v0, 0x7f01` 恰好安全——别把这份巧合当规律用。
- **`.registers` 声明不足**。`.registers 1` 却用 `v5`，汇编通过，装上才 `VerifyError`。这是最典型的「编译过、运行崩」。
- **`move-result` 位置错**。规范要求它紧跟 `invoke-*`，但：
  - 中间插 `:cond_0` 标签**无害**（标签不是指令，不占指令位）；
  - 真正非法的是从别处 `goto` 进那段再执行 `move-result`，实测同样 `rc=0`。

- **引用了不存在的方法重载**（`NoSuchMethodError`）。`invoke-*` 只校验语法，**不校验目标类里有没有这个方法**：

    ```smali
    # apktool b 返回 EXIT=0，装到设备上才炸
    invoke-static {v1, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/Throwable;)I
    ```

    `android.util.Log` 只有 `e(String, String)` 和 `e(String, String, Throwable)`，**没有**两参数带 `Throwable` 的版本。
    运行时报的原文是
    `No static method e(Ljava/lang/String;Ljava/lang/Throwable;)I in class Landroid/util/Log; or its super classes`。
    危险之处：它常出现在你补的「兜底 catch」里 —— 本想记录异常，结果把兜底路径本身变成了新的崩溃点，而 `apktool b` / `aapt2` / dex 校验全都不拦。

    判定方法：新增 `invoke-*` 前，用三种证据之一确认签名真实存在 —— ① 官方 API 文档；② 工程里已有的同类调用点（在反编译树里 `grep` 方法名）；③ 反编译一个已知能跑的 APK 看它怎么写。**凭记忆写重载不算证据。**

    真实案例（2026-11，Android 16 / apktool 3.0.1）：给 `catch (Throwable)` 补日志时写了两参数 `Log.e(tag, ex)`，构建全绿、安装正常，
    但 ping 功能整个不可用 —— App 把 `No static method e(...)` 这行直接显示在结果区了。定位手段是**把界面上被截断的错误文本完整打印出来**，
    再装回上一版对照确认。

### 2.3 只能靠逻辑判断

- **异常范围**：`try` 块内新增指令要确认没被已有的 `catch` 覆盖，否则异常会被错误吞掉。
- **`.registers` 与 `.locals` 口径**：前者含参数寄存器，后者不含。算错了一边是 `VerifyError`，但工具不会替你算。

- **条件码的语义与英文缩写的直觉相反**（最容易一次错好几处）。`if-*z` 系列里的 `z` 指「与 0 比较」，
  而 `ne` / `ge` 描述的是「比较结果非零 / 非负」，**不是**对源码意图的描述：

    | 指令 | 真正含义 | 常见误读 |
    |---|---|---|
    | `if-eqz vA, :L` | `vA == 0` 时跳 | — |
    | `if-nez vA, :L` | `vA != 0` 时跳 | 「不相等就跳」→ 反了 |
    | `if-ltz vA, :L` | `vA < 0` 时跳 | — |
    | `if-gez vA, :L` | `vA >= 0` 时跳 | 「小于 0 就跳」→ 反了 |
    | `if-gt vA, vB, :L` | `vA > vB` 时跳 | — |
    | `if-ge vA, vB, :L` | `vA >= vB` 时跳 | — |

    两条高频踩点：

    - `String.equals` 返回 **0 表示不相等**，所以「不相等就继续看下一个」必须写 `if-eqz`；
    - `cmp-long` 的结果是 −1 / 0 / 1，判「结果为负（失败）」必须写 `if-ltz`。写成 `if-gez` 会把**成功**判成失败。

    审查动作：**逐个 `if-*` 与它注释声称的意图对表**，不要顺着代码读。反向分支读起来完全通顺，
    `apktool b` 也全绿，只有运行期才暴露 —— 单看代码看不出来。

    真实案例（2026-11，一份 165 行的手写 `Bridge.smali` 里三处反了）：
    ① `-t` 扫描用 `if-nez` 把「不相等」当成命中，快速路径永不生效（每个样本都静默回退 `exec`）；
    ② host 判空用 `if-nez`，host 非空时反而跳去失败；
    ③ `cmp-long` 后用 `if-gez`，native 成功时被判失败。
    三处都躲过了人工阅读与 `apktool b`，最后靠「native 侧打成功日志、Java 侧打回退日志，两侧结论互相矛盾」才定位到。

审查方法：`apktool b` 过了只清掉 2.1；2.2 和 2.3 必须逐个方法人工过，或者装到设备上看 logcat。

想自己复核上面任何一条：建一个只有 `apktool.yml` + `AndroidManifest.xml` + `smali/a/A.smali` 的最小工程，`apktool b` 它，几秒出结果。本节所有报错原文与 `rc` 都是这么测出来的，不是抄的。

### 2.4 so / JNI：加载失败会伪装成「静默降级」

`dlopen` 失败时，只要你的代码写了 `catch` 回退，功能看起来**完全正常**，只是优化没生效。
所以改了 native 代码后，第一条要看的不是功能，而是**加载日志**：

- 成功：自己打的 `xxx: loaded`（或 `JNI_OnLoad` 的日志）；
- 失败：`UnsatisfiedLinkError: dlopen failed: cannot locate symbol "..."`。

**最常见的一种（实测踩过）**：用了 GCC 内建原子 `__atomic_*` 做锁。GCC 会为它生成
`__aarch64_swp1_acq` 这类辅助符号，该符号由 **`libatomic`** 提供 —— 而 **Android 没有独立 `libatomic.so`**，
`-nostdlib` 只链 libc 时必然缺符号，`dlopen` 直接失败。

| 想要 | 换成 | 为什么 |
|---|---|---|
| 原子 CAS / 自旋锁 | `pthread_mutex_trylock` + `pthread_mutex_unlock` | bionic 把 pthread 并入 libc，符号一定在 |
| 极轻量标记 | 内联汇编 `ldaxr` / `stxr` | 零外部符号依赖 |

用 `pthread_mutex_t` 时注意尺寸：bionic 64 位是 40 字节。建议用**偏大的 union**（如 64 字节）包住，
宁大不小 —— 尺寸写小会越界写坏相邻静态变量。

自查命令（不用装机）：

```sh
readelf --dyn-syms libfoo.so | grep ' UND '   # 期望全部带 @LIBC，不能出现 __aarch64_* / __atomic_*
readelf -d libfoo.so | grep NEEDED           # 只应有 libc.so
```

另外要有一个能证明「真的加载成功」的信号（自定义 `loaded` 日志、或把加载结果写进静态字段并打印），
**别把 `catch` 当验证** —— 捕获成功不等于功能生效。

## 3. 资源层的连带关系

- 字符串/数组/颜色在 `resources.arsc` 里，**多语言是分开的**。只改 `values/strings.xml` 而设备语言走 `values-xx`，成品看起来像没改。
- 新增资源会改变 `R` 常量索引，反编译工程里**手写的 ID 与 `public.xml` 必须同步**，否则 `Resources$NotFoundException`。
- 图片/矢量图替换：注意 `dpi` 目录与 `android:src` 的引用；改了格式（PNG → vector）要确认 minSdk 支持 vector。
- 排序：`resources.arsc` 需要保持对齐，回编译工具一般会处理，但如果手工改过要重新打包而不是只替换。

## 4. manifest 层的三个陷阱

1. **运行时覆盖**：代码里 `PackageManager.getApplicationInfo().metaData` 动态写入的 key，改 manifest 无效（甚至会和运行时值冲突）。
2. **签名变更**：debug 签名替换官方签名后，应用自身的完整性校验、`signature` 权限、以及与其它应用共享 uid 的机制都会失效。
3. **组件导出**：改 `exported` / 增删 `intent-filter` 属于安全面变更，要单独评估（导出的组件可被任意应用调起）。

## 5. 混淆：定位方法比读代码更重要

被 R8/ProGuard 全程序优化后，**库类名也会被重命名**（`AdView` → 某个短名），所以「搜类名」经常零结果。可用手段按可靠性排序：

1. **搜字符串**：SDK 的初始化日志、tag、URL、错误文案通常保留。
2. **搜特征调用**：如 `->setAdUnitId(`、`->loadAd(` 这类 API 名字（方法名同样可能被改，但第三方 SDK 的公开 API 常被 keep 规则保留）。
3. **从调用点反查**：找到唯一的应用侧调用点，比找库内部实现有效得多。
4. **按资源引用反查**：布局 XML 里的自定义 View 类名会被重命名，但 layout 名字通常保留。

审查要点：**结论必须说明是怎么定位到的**。写「在 xxx.smali 里」而不写依据，等于不可复核。

## 6. 验证口径（「改完了」不等于「生效了」）

一次合格的验证至少五条：

1. 能安装（签名/最低 SDK/ABI 不冲突）；
2. 能启动到目标界面，且 `logcat` 无 `FATAL EXCEPTION`；
3. 目标行为**可观测地**改变（不是「感觉没了」，而是计数、日志、界面元素的有无）；
4. 冷启动一次再确认（有些初始化只在首次进程启动时发生）。
5. **证据要落到下游持久化数据，而不是界面呈现**。界面有数字、图表在动，只能证明「有东西被画出来了」。
   去找到该功能真正落库 / 落盘的那份数据（Room/SQLite、`shared_prefs`、导出文件、服务端请求体），核对里面的**计数与取值**。
   真实案例：某改包版 ping 界面显示平均 1–2 ms、`logcat` 无异常、子进程数为 0（三项证据齐了），
   但 App 自己的 `ping_table` 里 `packetReceivedCount=0`、26 个 `rttValues` 全是 `-1` —— 实际是 100% 丢包。
   原因是假 `Process` 的输出行形状与真 `ping` 不一致（`icmp_seq` 写死、行尾无换行），解析器逐条判失败。
   判据：**能在库或文件里指到那个数字，才算验证过**；指不到就是还没验证。
   （没有 `sqlite3` CLI 时用 `python3` 的 `sqlite3` 模块直读；带 WAL 的库要把 `-wal` / `-shm` 一起拷出来。）

反例（都是真实常见的假验证）：「装上了就算成功」「进程活着就算成功」「搜索结果为空所以功能已移除」——最后这条尤其危险，混淆会让搜索永远为空。

## 7. 自查清单

1. 改动落在哪一层？这一层在运行时会被覆盖吗？
2. 改的是本地值还是服务端下发值？
3. smali 约束过了吗？`apktool b` 只能证明 2.1 那四条；2.2 / 2.3 要逐个方法人工看（`.registers` 够不够、`const/16` 有没有被截断、`move-result` 有没有被跳转跨过）。
4. 资源 ID 与 `public.xml` 是否同步？
5. 多语言目录是否都覆盖到？
6. manifest 改动是否有运行时副作用？
7. 定位混淆代码的依据是否写清？
8. 验证是否包含「可观测的行为变化 + 冷启动」？
9. 是否新增/修改了**跨线程共享的状态**（静态字段、单例、复用中的 fd/连接、缓存）？若判断「不会并发」，是否写进了「存疑」而不是当成已证明？

## 8. 边界

本档不评价「该不该去广告 / 该不该改包名」这类判断。它只回答：这个补丁会不会真的按预期运行，以及它的证据链是否够硬。