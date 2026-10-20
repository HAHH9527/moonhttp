# Implementation Plan: 连接池：租约、驱逐与毒化（M1-P04）

**Branch**: `004-m1-p04-connection-pool` | **Date**: 2026-10-19
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from
`/specs/004-m1-p04-connection-pool/spec.md`
（含 2026-10-19 Clarifications 五问与既定裁决前提 P1–P10）

**Note**: owner 批准自主规划（不提问、按证据裁决）；research.md 承载全部
源码级证据与决策（R1–R8），本文引用不重复。

## Summary

交付 moonhttp 的 HTTP/1.x 连接池（L1 杠杆本体）：按 `Address`（直连三元组）
复用 `@http.Client` 连接——`Lease` 独占租约、LIFO 空闲栈归还、惰性 + 显式
驱逐（D15：池不养常驻任务，只暴露同步 `evict_expired()`/`evict_all()`，
超期判定为注入式时钟的纯函数）、毒化路径（池只认 `poison()`，P4）。
宿主 `src/client`（现 placeholder 占位）；同步扩展 P03 夹具可观测性
（累计 accept 计数 / 每连接请求数 / per-route 次序脚本，P9 裁决，
implement 首片）。无泄漏判据按 Q04 双证据（夹具累计 accept == 池内新建；
池侧 conn_id 基数守恒），native/wasm 同用；性能量化验收归 P10，本包只断言
机制正确性与无泄漏。

## Technical Context

**Language/Version**: MoonBit，moon ≥ 0.1.20261012（`--deny-warn`/
`fmt --check`/`-f` glob/`-p` 包名语义已核证，003 research P-h）

**Primary Dependencies**: `moonbitlang/async@0.22.x`（registry，钉 0.22.x）；
仅用 `@http`/`@async` 公开 API（http mbti 能力清单见 research R1）；本模块
core 包（P01 已交付，`HttpUrl::equal/hash` 先例）；**零新增外部依赖**
（`moonbitlang/x` 出现次数 0，对齐 003）

**Storage**: N/A（纯内存池）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；白盒承载
时钟注入与 conn_id 守恒断言；命名 `P04-<域><序> 描述`（R8）

**Target Platform**: native + wasm 双绿为门（✅ 指 wasm，非 wasm-gc）；js
**未验证**（D14/D9，挂 F9 随 M5 收口，本包不写 js 路径）；wasm-gc 排除

**Project Type**: library（门面包 `src/client` + internal 夹具扩展）

**Performance Goals**: 机制正确性与无泄漏为本包交付物；池自身开销设计约束
亚微秒级（Map 查找+栈弹出+锁取放，宪法 II）；「≥20×」量化门禁归 P10。
性能按臂分述（03 §6）：新建 ≈10ms/请求（1× 基线）→ 单连接顺序复用
415–431µs（≈24×）与池 K=16 并发 178–196µs（47–56×）是**两条臂**。

**Constraints**: 建连只经 `Client::Client(uri)`（D13）；池不养常驻任务
（D15）；无 fd 探测（C-7 缺口，Q04 双证据替代）；禁止 sleep 串联推进时间
（R2 注入时钟）；`src/client/placeholder` 本包不删（P6）

**Scale/Scope**: 1 个门面包（池）+ 1 个 internal 夹具扩展；FR-001～FR-018、
SC-001～SC-007；约 4 个测试文件（R8 表）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过，含两项显式否决**：全部设计仅经 `@http`/`@async` 公开 API（R1 能力清单逐条给锚点）；不 fork/复制/vendor 上游源码；`moonbitlang/x` 零引用。**显式否决 ①**：自写 `extern "C"`/C stub/FFI 探测 fd——上游无 fd/shutdown 是能力缺口，私有补能力违反零 fork 原则（Q04 双证据已替代，无场景被阻塞）。**显式否决 ②**：直接取 `@socket.Tcp` 自行建连绕过 `@http.Client`——破坏单请求在途状态机前提（FR-001 的依据），且等价重写上游发送路径 |
| II 性能优先 | 通过：本包是「已实测杠杆不回归」的核心载体（池化 47–56×）；池操作设计约束亚微秒级，量化验收归 P10 门禁；C3 保留 Mutex 的性能噪点由 P10 基准证实/证伪（Clarifications Q4） |
| III OkHttp 语义对齐 | 通过：池化语义对齐 03 §3.1–§3.4（OkHttp ConnectionPool 对应物）；有意差异显式记录两处——`per_host_total` 非硬上限 vs Dispatcher 每主机上限（FR-013，P10 需要 K=64）；`stale_evictions` 语义扩展（data-model 实体 2 注记 + research R4.4 两处登记） |
| IV 验收场景与测试先行 | 通过：FR-001～FR-018 逐条映射元测试（下表）；断言优先 `assert_eq`/`assert_true`；全部测试基于 P03 本地夹具（宪法 IV 反外部网络）；**禁 sleep 串联**——时间推进走注入时钟（R2） |
| V Target 策略 | 通过：native ≥ wasm 双绿为门（✅ 指 wasm）；js 未验证（D14/D9，不写 `#cfg(js)` 空实现，js 路径归 P05/P09）；wasm-gc 排除 |
| VI 简洁与接口纪律 | 通过：公开面最小化（R6：evict 入口 `-> Unit`，观测走既有计数器；时钟/conn_id/内部结构不进 `.mbti`）；`placeholder` 保留（P6）；`.mbti` 逐次审视入六门，冻结面契约见 contracts/pool-api.md |
| VII 中文表达 | 通过：注释/文档全中文；commit 走 Conventional Commits 中文描述 |

**Phase 1 复核**：设计落定后无新增违宪点。需持续盯防项＝同步路径
`try_acquire` 失败必须 abort 而非静默跳过（R3——静默跳过会把 FR-006
不变量破坏转化成验收 flaky）。

## Project Structure

### Documentation (this feature)

```text
specs/004-m1-p04-connection-pool/
├── spec.md                    # W05/W06 产物（Clarifications 五问已闭）
├── plan.md                    # 本文
├── research.md                # R1–R8：能力清单/时钟/锁策略/选型/夹具/观测面
├── data-model.md              # 四实体/不变量/状态迁移/两条 W06 契约
├── contracts/
│   └── pool-api.md            # .mbti 冻结面事前契约（SC-007 对账面）
├── quickstart.md              # 六门 + 分场景 + 长跑显式执行（-p 全包名）
└── checklists/requirements.md # 16/16（specify 阶段产物）
```

### Source Code (repository root)

```text
src/
├── client/                        # 池宿主（门面包，现有骨架）
│   ├── moon.pkg                   # 增依赖 async / async/http / core
│   ├── client.mbt                 # 新：Address/ConnectionPool/Lease
│   ├── address_test.mbt           # 新：FR-014 键隔离/规范化（黑盒）
│   ├── pool_test.mbt              # 新：US-1/3/4 场景（黑盒独立驱动）
│   ├── pool_wbtest.mbt            # 新：时钟注入/conn_id 守恒/终结幂等（白盒）
│   ├── pool_longrun_test.mbt      # 新：US-2 场景 2 双证据长跑（默认跳过，C5）
│   └── client_test.mbt            # 既有 placeholder 测试保留（P6）
├── internal/
│   └── fixtures/                  # P03 夹具扩展（implement 首片，P9）
│       ├── scripted_server.mbt    # 增量：计数/请求数/次序脚本（R5）
│       └── scripted_server_test.mbt # 增量：F-5/F-6/F-7 自证（P04-FIX*）
└── core/                          # 零改动（.mbti 期望零 diff）
```

**Structure Decision**: 池入既有门面包 `src/client`（README 第 5 节包布局
裁决：执行管线/池/超时/Dispatcher 入门面包）；不拆子包（宪法 VI；长跑
隔离走 `#skip` 主案，见 R8）。夹具扩展落在既有 internal 包内（P9），
`.mbti` 增面逐处归因（T025 先例）。

## 四个决策节（细则见 research.md / data-model.md / contracts/）

**(D-1) 研究与决策记录 → research.md R1–R8**：R1 上游 `@http.Client`
能力清单（C-1～C-11 逐条锚点；`Client::drop` 仅见 mbti:66 无源码、不使用；
Host 头构造期固化 client.mbt:58 ⇒ 键必含端口）；R2 注入式时钟＝私有
`now_ms : () -> Int64` + 同包白盒私有构造入口，推进虚拟时间零 sleep；
R3 锁策略＝异步路径 `acquire()`/同步路径 `try_acquire`（FIFO 恒 false
陷阱 → 失败即 abort 不静默跳过；不变量「临界区无 await」下 try_acquire
恒成功，论证见 R3）；R4 选型＝`Array` 尾部 push/pop 做 LIFO、禁依赖
Map 迭代序、Address 含端口；R4.4＝stale_evictions 与 03 §3.4 的偏移
登记（第二处）；R5 夹具扩展；R6 evict 入口 `-> Unit`（最小公开面）；
R7 双证据执行设计；R8 测试组织与 `-p` 假验证警示。

**(D-2) 夹具扩展归属 → research.md R5 + plan「夹具能力清单」**：F-1～F-4
现有、F-5/F-6/F-7 待建（implement 首片），`.mbti` 增面逐处归因 FR/US。

**(D-3) `.mbti` 冻结面 → contracts/pool-api.md §1**：`src/client` 从
「仅 placeholder」扩为 Address（new/三访问器/equal/hash）+ ConnectionPool
（new(max_idle?, keep_alive_ms?)/acquire/evict_all/evict_expired/
stale_evictions/per_host_total）+
Lease（release/poison）；`src/core` 期望零 diff；命名全 snake_case；
`placeholder` 保留（P6）。

**(D-4) 数据模型 → data-model.md**：Address/PoolInner/IdleLease/Lease
四实体字段、七条不变量、conn_id 状态迁移图；两条 W06 契约落点——终结
幂等（released 标记 + no-op 契约，实体 4/不变量 5）与 stale_evictions
只计超期剔除（实体 2 注记 + research R4.4 两处偏移登记）。

## 夹具能力清单（现有 vs 待建；细则 R5）

| # | 能力 | 状态 | 锚点/去向 |
| --- | --- | --- | --- |
| F-1 | keep-alive 多请求连接处理 | 现有 | serve_connection :212 |
| F-2 | 串行 accept + spawn_bg 并发承载 | 现有 | serve_n :269（T008 裁决） |
| F-3 | 在途/高水位观测 | 现有 | :65-66/:288-302/:473（口径不满足双证据） |
| F-4 | 路由编排（echo/帧形态/重定向） | 现有 | routes :62、mount 覆盖式 :170 |
| F-5 | 累计 accept 连接数（外部证据） | **待建** | → FR-009/US-2 场景 2 |
| F-6 | 每连接请求数（复用度观测） | **待建** | → 长跑 keep-alive 自证 |
| F-7 | per-route 次序脚本 | **待建** | → FR-010 集成桩/US-4 场景 2 |

## FR/US ↔ 元测试映射表（包级 DoD-2 对账面）

| spec 条目 | 元测试（文件·盒型） | 状态 |
| --- | --- | --- |
| FR-014 键隔离/规范化/equal/hash | address_test·黑盒（P04-E*） | 计划 |
| FR-001 独占 / FR-004 LIFO / US-1 场景 1-3 | pool_test·黑盒（P04-US1*）+ pool_wbtest（id 断言） | 计划 |
| FR-002 归池判定 / FR-003 不回池三路径 / US-4 场景 1-3 | pool_test·黑盒（P04-US4*，含 F-7 次序桩） | 计划 |
| FR-005 显式驱逐 / US-3 场景 1-2 | pool_test·黑盒（P04-US3*）+ pool_wbtest（时钟注入推进） | 计划 |
| FR-006 临界区无 await | pool_wbtest·白盒（不变量断言 + R3 防御路径） | 计划 |
| FR-007 计数可读与口径 | pool_test + pool_wbtest（Q3 口径：evict_all/毒化/栈满不加） | 计划 |
| FR-008 建连公开构造 | pool_test·黑盒（D13；`--deny-warn` 门下零 deprecated） | 计划 |
| FR-009/US-2 双证据 | pool_wbtest（内部守恒）+ pool_longrun_test（外部 accept 计数） | 计划 |
| FR-010/US-4 场景 2（Connection: close 桩） | pool_test·黑盒（F-7 次序脚本桩管线） | 计划 |
| FR-011 release 无状态参数（P5） | pool_test·黑盒（残 body 契约形态）+ 契约面审（contracts §1 无枚举） | 计划 |
| FR-012 命名 | contracts §1 冻结面审（.mbti 零 camelCase） | 计划 |
| FR-013 观测非上限（K=64 形态） | pool_test·黑盒（公开观测器可断，并发租借不受 per_host_total 约束） | 计划 |
| FR-015 acquire 失败透传 | pool_test·黑盒（P03 connect 拒绝注入） | 计划 |
| FR-016/SC-007 冻结面 | moon info 审视 vs contracts/pool-api.md §1 | 计划 |
| FR-017 P07 兜底声明 | 非测试项（spec 如实登记；不构造「取出即可用」断言） | 不适用 |
| FR-018/US-4 场景 4 终结幂等 | pool_wbtest·白盒 + pool_test 黑盒（重复 release 守恒） | 计划 |
| US-2 场景 1（K=8 并发 100） | pool_test·黑盒（P04-US2*；serve_n(n≥K) 预启动，见风险 R2） | 计划 |
| SC-002 长跑双证据 | pool_longrun_test（默认跳过，显式执行，quickstart §3） | 计划 |

## 验收口径（收口六门 + 专项；命令全录 quickstart.md）

### 收口六门

1. `moon check --target native --deny-warn`
2. `moon check --target wasm --deny-warn`
3. `moon test --target native --deny-warn`（默认套，不含长跑——C5）
4. `moon test --target wasm --deny-warn`（同上）
5. `moon fmt --check`
6. `moon info` 后审 `.mbti` diff（core 零 diff；client = contracts §1；
   fixtures 增面逐处归因；最终轮先 `moon clean`）

### ⚠️ `-p` 假验证警示（必须写进任务口径）

`moon test -p` **只认包名**（`hahh9527/moonhttp/client`）；写目录路径
**跑 0 个测试却返回 exit 0**（假绿）。所有分包命令用全包名，执行后检查
`Total tests:` 非 0（quickstart §0）。

### 长跑显式执行（裁决 C5 主案，2026-10-20 核证定案）

- 主案：长跑条目声明 `#skip`（默认 `moon test` 不计数、不执行）+ 显式跑
  `moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*"
  --include-skipped`（skip 语法 2026-10-20 host 实测核证：双 target、
  含无属性对照组；禁以 `#cfg` 充当跳过——证据见 research R8）。
- 回退仅留档（非 live 备选）：T018 首步三连自检失败即停手报告、回
  research R8 重议，不得自行切换机制。
- 通过证据（Q04 双证据）登记进包级 DoD-1；wasm 分档数值 implement 期
  按 t004-record.md 校准。

## 收尾事项

1. 六门全绿 + `.mbti` diff 审视结论归档（对账 contracts/pool-api.md §1）。
2. 长跑双证据记录（native/wasm 各一份：规模、accepted_total、守恒断言
   结果）随交付归档，登记进包级 DoD-1。
3. 长跑隔离机制核证已归档（2026-10-20）：skip 语法 host 实测通过（双
   target、含无属性对照组），主案 `#skip` + `--include-skipped` 定案
   （research R8）；T018 首步仅余包内三连回归自检。
4. `src/client/placeholder` 的删除评估留给 implement 收口片（P6；本包
   不删，基线 160 记账不被搅动）。

## Complexity Tracking

> 无宪法违例，无需豁免记录。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无） | — | — |

## 风险登记（plan 视角最高风险三处）

| # | 风险 | 影响 | 处置 |
| --- | --- | --- | --- |
| R1 | 时间驱动抖动：真实时钟下「超期→驱逐」断言踩墙上钟竞速（sleep 串联是反模式） | US-3/SC-004 确定性 | 注入时钟（R2）零 sleep；白盒推进虚拟时间；确需真实时延的场景（无）不进本包。容差先例 ±50ms（scripted_server_test.mbt:67/:107）仅属夹具自身时延元测试，池侧不引入 |
| R2 | 夹具 `serve_n`（:269）串行 accept 可能把排队延迟伪装成「池失效/超时」——客户端并发打满时 accept 慢不是池的错 | US-2 场景 1/长跑判据 | 先 `serve_n(n≥K)` 预启动 accept 循环再放行客户端并发（n≥并发数，连接已在途排队处理）；F-3 高水位 ≥2 佐证并发处理真实发生；必要时用 F-6 每连接请求数区分「连接没建」与「请求没复用」 |
| R3 | RST/关闭形态不可稳定断言（native vs wasm/moonrun 依 OS 与在途数据而变，P03 观测清单口径） | 协议错误毒化行的判据 | 只断 ∈ {BadRequest, ReaderClosed}（spec DoD-2 映射口径），禁扩集；关闭形态断言不进本包（B-10 观测清单已由 P03 交付） |
