# Tasks: 连接池：租约、驱逐与毒化（M1-P04）

**Input**: Design documents from `/specs/004-m1-p04-connection-pool/`

**Prerequisites**: plan.md（必读，四决策节与验收口径）、spec.md（Clarifications
五问 + P1–P10 前提 + FR-001～018）、research.md（R1–R8）、data-model.md
（四实体/七不变量）、contracts/pool-api.md（冻结面契约）、quickstart.md
（验证命令与 `-p` 假验证警示）

**Tests**: 本包全部任务按宪法 IV「验收场景与测试先行」执行——每任务的自证
元测试与实现在**同一任务内成对出现（先红后绿）**；「只写实现、测试另立
任务补」为违规排布（003 tasks:7 口径）。双 target（native/wasm）为每对
任务的默认验收；长跑用例按裁决 C5 默认排除六门。

**Organization**: 按用户故事分组（US-1～US-4，spec 优先级）；夹具扩展与
池骨架为 Foundational 阻塞项。**阶段顺序说明**：US-4（P2）按 owner 示踪
弹顺序（工单 (iii)：Lease 独占 + poison + 残 body 契约先于驱逐切片）排在
US-3 之前；US-2 压轴，因其长跑守恒口径消费全部关闭路径（毒化/栈满/超期）
在场后的三集合守恒（research R7）。Story 标签与 spec 编号一一对应，优先级
标注不受阶段顺序影响。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1/US2/US3/US4，对应 spec 用户故事 1～4）
- 描述含精确文件路径

## Path Conventions

- 池宿主：`src/client/`（门面包，现 placeholder 骨架）
- 夹具扩展：`src/internal/fixtures/`（P9 裁决，implement 首片）
- 零改动：`src/core/`（P04 不触碰；`.mbti` 期望零 diff）

---

## Phase 1: Setup（共享基线）

**Purpose**: 动工前固化基线，供后续 diff 归因与回归对照

- [ ] T001 记录动工前基线（可机器复核、免构建只读部分先行）：静态测试计数
  `grep -rhP '^\s*(async\s+)?test\s' src --include='*_test.mbt' --include='*_wbtest.mbt' | wc -l`
  当前实测 **== 160**（18 个文件）；再依次运行六门（`moon check --target
  native/wasm --deny-warn`、`moon test --target native/wasm --deny-warn`
  ——双 target 运行时判据 `Total tests: 160`、`moon fmt --check`、
  `moon info`），将六门结果与 `src/client/pkg.generated.mbti`（现仅
  placeholder）、`src/core/pkg.generated.mbti`、
  `src/internal/fixtures/pkg.generated.mbti` 快照存入本特性目录
  `baseline.md`（对照物：Phase 7 的 T024/T025）

---

## Phase 2: Foundational（阻塞项：夹具扩展 + Address + 池骨架）

**Purpose**: 夹具可观测性是 US-2/US-4 判据面（P9 裁决首片）；Address 与池
骨架被全部故事消费

**⚠️ CRITICAL**: 本阶段未完成前不得开始任何 US 行为任务

- [ ] T002 [P] 夹具可观测性扩展 F-5/F-6/F-7（首片，先红后绿）：
  `src/internal/fixtures/scripted_server_test.mbt` 写自证元测试
  P04-FIX①②③（红：`accepted_total` 访问器不存在、无每连接请求数、
  同路由无法次序编排）→ 实现 `src/internal/fixtures/scripted_server.mbt`：
  `priv mut accepted_total`（accept 成功点 +1）+ `accepted_total() -> Int`；
  `priv conn_request_counts : Array[Int32]`（按 accept 序号）+ 拷贝语义
  访问器；`RouteScript = Single | Sequence(Array)`（第 i 次命中取
  `min(i, len-1)` 末位驻留；既有 mount 覆盖式语义不变，routes :62/:170）。
  **`.mbti` 增面逐处归因（T025 口径：internal 非对外承诺但须有意识）**：
  `accepted_total()` → FR-009 外部证据/US-2 场景 2；`conn_request_counts()`
  → 长跑 keep-alive 复用自证；次序脚本类型与 mount 重载 → FR-010 集成
  桩/US-4 场景 2（research R5）
- [ ] T003 [P] Address 类型（先红后绿）：`src/client/address_test.mbt` 写
  P04-E①～⑤（红：无 Address 类型）→ 实现 `src/client/client.mbt`
  `Address::new(scheme~, host~, port~)`（规范化单点收口：scheme/host
  小写化、IPv6 剥方括号；noraise）/`scheme/host/port` 访问器/`equal`/
  `hash`（形态沿 P01 `HttpUrl::equal/hash` 先例，core mbti:76-79）。
  断言面：跨端口不同键（E①）、跨 scheme 不同键（E②）、host 大小写
  规范化同键（E③）、IPv6 括号剥离（E④）、equal/hash 一致且可作 Map 键
  （E⑤）（FR-014；键含端口的物理依据＝client.mbt:58 Host 构造期固化）
- [ ] T004 池骨架 + 注入式时钟（先红后绿）：`src/client/client.mbt` 实现
  `ConnectionPool`/`PoolInner`/`IdleLease`/`Lease` 结构骨架（data-model
  实体 2～4；`Mutex[PoolInner]` 按 C3 裁决保留）+ 公开构造
  `ConnectionPool::new(max_idle? : Int, keep_alive_ms? : Int)`（缺省
  5 / 300_000；`max_idle > 0` 违反即 panic）+ 私有构造
  `priv with_clock(max_idle~, keep_alive_ms~, now_fn~)`（research R2）；
  `src/client/pool_wbtest.mbt` 写 P04-FR①（注入时钟序列生效——
  `now_ms()` 返回受控值）与 P04-FR②（构造校验：max_idle=0 构造即
  panic）→ 转绿；`moon info` 产出首版冻结面（对 contracts/pool-api.md
  §1：此时仅 Address + new + placeholder；计划外公开项为零）

**Checkpoint**: 夹具判据面就绪、Address/池骨架可用——US 行为任务可以开始

---

## Phase 3: User Story 1 — 租借与归还（Priority: P1）🎯 MVP

**Goal**: 执行管线（P05）可用 `acquire(addr)` 拿独占 Lease、`release()`
归池或关闭：新建/复用/LIFO/栈满全链路（US-1 场景 1～3 + FR-001/002/004/
008/015）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm`（`pool_test.mbt` + `pool_wbtest.mbt`）——`@http.Client` 原语
+ Lease 手动驱动，不经 P05（spec 独立测试口径）

### Implementation for User Story 1（每任务 = 元测试先红 → 实现转绿）

- [ ] T005 [US1] acquire 新建与失败透传（FR-008/FR-015）：
  `pool_test.mbt` 写 P04-US1①（空池 acquire → 新建连接、
  `per_host_total(addr)` 递增为 1；uri 形态 `\{scheme}://\{host}:\{port}`
  仅经 `Client::Client(uri)`——D13）与 P04-E⑥（P03 注入 connect 拒绝 →
  错误原样透传、`per_host_total` 不虚增、白盒 idle/borrowed/closed 零
  变化，FR-015）→ 实现 acquire 建连路径：锁内查桶（无命中）→ **解锁后
  建连**（FR-006 临界区无 IO）→ 成功才 `per_host_total` +1 并入 borrowed
  （data-model 不变量 6）
- [ ] T006 [US1] release 归池 + LIFO（FR-002/FR-004）：`pool_test.mbt` 写
  P04-US1②（release 干净 Lease 后再次 acquire 同 Address → 弹出**同一
  连接实例**（conn_id 相同，白盒辅证）、无新建）→ 实现 release 归池判定
  （同步 `try_acquire` 失败即 abort，research R3；未毒化 ∧ idle 未满 →
  push 尾部、`idle_since = now_ms()`；否则 `close()`）与 acquire 命中
  `pop()`（尾 = 最热）
- [ ] T007 [US1] 栈满 close 不入栈（FR-003 分支）：`pool_test.mbt` 写
  P04-US1③（`max_idle=1`：两条连接先后 release → 第二条被 close、不入
  栈；复用不受影响）→ 实现栈满分支（不回池即 close 家族，不计
  `stale_evictions`，FR-007 口径）
- [ ] T008 [US1] 独占白盒（FR-001）：`pool_wbtest.mbt` 写 P04-FR③
  （并发 acquire N → N 个互异 conn_id；borrowed 集合两两不交；任意交错
  后守恒恒等式成立——data-model 不变量 1/5）→ 实现侧结构校验
  （pop 移除 + borrowed 去重）

**Checkpoint**: US-1 独立可用——租借/复用/栈满/失败透传全链路
native+wasm 双绿（MVP 增量）

---

## Phase 4: User Story 4 — 毒化路径（Priority: P2；按 owner 示踪弹顺序提前）

**Goal**: 不可复用连接绝不回池：poison 标记、残 body 调用方契约、
`Connection: close` 集成桩、终结幂等（US-4 场景 1～4 + FR-003/010/011/
018）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P04-US4*"`（黑盒）+ `-f "P04-FR*"`（白盒幂等/守恒）

- [ ] T009 [US4] poison 标记 + release 不回池（FR-003/FR-011）：
  `pool_test.mbt` 写 P04-US4①（毒化 Lease release → 连接关闭、idle 不
  增长；再 acquire 得到的是新建连接）→ 实现 `Lease::poison()`（仅置
  `poisoned` 标记，不碰锁）与 release 判定毒化分支（→ close，**不加
  `stale_evictions`**，FR-007 口径；池只认 poison 标记，P4/Q06）
- [ ] T010 [US4] 残 body 调用方契约（P5/Q07）：`pool_test.mbt` 写
  P04-US4②（响应体未消费完的 Lease 按调用方契约先 `poison()` → release
  不回池；`skip_response_body()` 后 release → 正常回池，两分支对照）→
  无新增实现（判定分支 T009 已就位）；本任务同时完成契约面审记录：
  `release` 无状态参数、无新增公开枚举（FR-011；对 contracts/pool-api.md
  §1 核对）
- [ ] T011 [US4] `Connection: close` 集成桩（FR-010/P4/Q06；F-7 消费）：
  `pool_test.mbt` 写 P04-US4③（T002 次序脚本：同路由第一响应正常可
  复用、第二响应携带 `Connection: close` → **测试内桩管线**读响应头
  判定后调用 `poison()` → release 不回池、后续 acquire 为新建）→ 实现
  侧零新增（池只消费 poison 标记）。**红线：判定/解析归 P05/P06
  （Q06），本任务禁止引入任何响应头解析任务或池侧解析代码；「端到端」
  验收归 P05 集成**
- [ ] T012 [US4] 终结幂等（FR-018）：`pool_wbtest.mbt` 写 P04-FR④（已
  release 的 Lease 再次 release / 释放后 poison → 均为 no-op；守恒恒等式
  保持，不变量 5）+ `pool_test.mbt` 写 P04-US4④（黑盒同断言：不重复
  入栈、不二次关闭）→ 实现 `released` 标记 no-op 短路（内部 bool 形态，
  不进公开面）

**Checkpoint**: 毒化四场景 + 终结幂等全绿；「不回池即 close」家族三条
路径（毒化/栈满/超期）中两条已闭合

---

## Phase 5: User Story 3 — 驱逐与 evict_all（Priority: P1）

**Goal**: 惰性 + 显式驱逐全量落地：注入时钟超期剔除、惰性顺手剔除、
`evict_all` 幂等、零空转（US-3 场景 1～2 + FR-005/007 + 边界两条）

**Independent Test**: `moon test -p hahh9527/moonhttp/client --target
native|wasm -f "P04-US3*"`（黑盒）+ `-f "P04-FR*"`（白盒时钟推进）

- [ ] T013 [US3] evict_expired + 注入时钟超期剔除（FR-005；R2 落地）：
  `pool_wbtest.mbt` 写 P04-FR⑤（`with_clock(keep_alive_ms=1000)` + 2 条
  空闲连接 → 虚拟时钟推进过阈 → `evict_expired()` 剔除 2 条：
  `stale_evictions` +2、idle 清空、未超期连接 0 误剔）与 P04-US3① 黑盒
  同断言 → 实现 `evict_expired`：全桶扫描自尾向头 splice（结果不依赖
  Map 迭代序，R4.2）；**同步路径 `try_acquire` 失败即 abort**（R3——
  静默跳过＝饥饿＋验收 flaky，禁止）
- [ ] T014 [US3] 惰性剔除（FR-005 下半：acquire/release 顺手剔除）：
  `pool_wbtest.mbt` 写 P04-FR⑥（超期连接在 acquire 命中前被顺手剔除——
  拿到的是新建连接且 `stale_evictions` +1；release 时超期条目不入栈）→
  实现 acquire/release 路径接入与 T013 共享的超期判定函数（时间语义
  单点，R2 不变量 7）
- [ ] T015 [US3] evict_all 幂等 + 计数口径（US-3 场景 2 + Clarifications
  Q3）：`pool_test.mbt` 写 P04-US3②（任意状态连续 `evict_all()` 两次 →
  无错误、idle 为空）→ 实现（清空全部桶逐一 `close`，borrowed 不动）；
  `pool_wbtest.mbt` 写 P04-FR⑦（口径钉死：`evict_all()` 关闭、毒化关闭、
  栈满关闭均**不加** `stale_evictions`；仅超期剔除三条路径 +1）
- [ ] T016 [US3] 零空转守护断言（spec 边界「无活动零成本」/D15）：
  `pool_wbtest.mbt` 写 P04-E⑦（构造含 2 条空闲连接的池 → 仅推进虚拟
  时钟 10×keep_alive、不调用任何入口 → idle 不变、
  `stale_evictions` == 0——证明池无常驻任务、无调用即无驱逐）。性质为
  **落笔即绿的护栏断言**（设计上无常驻任务，若红即实现被引入了后台
  任务，显式违规 D15）

**Checkpoint**: 驱逐切片闭合；「不回池即 close」三路径全部在场；US-1/
US-3/US-4 场景 native+wasm 双绿

---

## Phase 6: User Story 2 — 并发正确性与长跑守恒（Priority: P1）

**Goal**: 并发交错无串响无重复出租（US-2 场景 1）；长跑双证据守恒
（US-2 场景 2 + FR-009/Q04）

**Independent Test**: 场景 1＝`moon test -p hahh9527/moonhttp/client -f
"P04-US2*" --target native|wasm`；场景 2＝显式执行（默认排除六门，C5），
命令见 quickstart §3

- [ ] T017 [US2] 并发租借串号检测（US-2 场景 1）：`pool_test.mbt` 写
  P04-US2①（K=8 池 × 并发 100 个「acquire→请求→校验回显 id→release」，
  echo 夹具 B-04；**先 `serve_n(n≥K)` 预启动 accept 循环再放行客户端**
  ——风险 R2：串行 accept 的排队延迟不得伪装成池失效）→ 全部请求 body
  与自身 id 匹配（串号 0）；如暴露实现缺陷在本任务内修复并补回归断言
- [ ] T018 [US2] 长跑双证据（US-2 场景 2 + FR-009/Q04/R7）：新增
  `src/client/pool_longrun_test.mbt`——首步**skip 语法冒烟核证**
  （research R8 主案：1 秒级验证 skip 属性；失败即切降级案 stress 独立
  包并记录）；随后 P04-LONGRUN①（native ≥10k 请求：外部证据
  `accepted_total() == 池内累计新建`（白盒 `next_conn_id - 1`）＋内部
  证据三集合基数守恒（不变量 5）＋复用度自证（存在 count ≥ 2 的连接，
  F-6））与 P04-LONGRUN②（wasm/moonrun 按 t004-record.md 吞吐分档
  降额，数值本任务校准并记录）。**判据只用双证据，禁 fd 计数（C-7）；
  时间推进只用注入时钟，禁 sleep 串联**；通过证据登记进包级 DoD-1

**Checkpoint**: 全部用户故事独立可用；六门默认套与长跑证据双轨就绪

---

## Phase 7: Polish & Cross-Cutting（收口）

**Purpose**: 冻结审视、门禁收口、对账与 DoD

- [ ] T019 `.mbti` 冻结审（FR-016/SC-007）：`moon info` 后逐条对照
  `contracts/pool-api.md` §1——`src/client` 冻结面计划外公开项为零
  （时钟/conn_id/内部结构不外泄）；`src/core/pkg.generated.mbti` 零 diff；
  `src/internal/fixtures` 增面与 T002 归因逐条对上（T025 口径）；
  `moon fmt --check` 通过
- [ ] T020 收口六门（最终轮先 `moon clean` 再全量）：`moon clean` →
  `moon check --target native/wasm --deny-warn` → `moon test --target
  native/wasm --deny-warn`（默认套 `Total tests:` ＝ 160 + 新增数，运行时
  判据不含长跑——C5）→ `moon fmt --check` → `moon info` 审视；随后按
  「B-xx ↔ 任务 ↔ 元测试映射表」对账包级 DoD-2（集成行标承载方），核对
  FR/SC 覆盖核对表（下两表）无缺项；确认包级 DoD-1 长跑证据已登记
  （T018 产出）
- [ ] T021 `placeholder` 处置记录（P6）：本包保留 `placeholder` 不删；
  评估「删除动作」的收口片归属与基线 160 记账影响，结论显式记录于任务
  产出（默认：保留，删除留待后续收口片）

---

## B-xx ↔ 任务 ↔ 元测试映射表（包级 DoD-2 对账面）

B-xx 编号 ＝ spec 包级 DoD-2 毒化五行 + 池行为切片（B-P01～B-P12）；
「集成承载」行不排任务（本包范围外，spec DoD-2 映射口径）。

| 行为 | 任务 | 元测试（文件·名） | 状态 |
| --- | --- | --- | --- |
| B-P01 毒化标记不回池 | T009 | pool_test.mbt P04-US4① | 计划 |
| B-P02 栈满不回池 | T007 | pool_test.mbt P04-US1③ | 计划 |
| B-P03 超期不回池（惰性+显式） | T013、T014 | pool_wbtest P04-FR⑤⑥ + pool_test P04-US3① | 计划 |
| B-P04 `Connection: close` 判定（池消费侧） | T011 | pool_test.mbt P04-US4③（次序脚本桩） | 计划 |
| B-P05 残 body 契约 | T010 | pool_test.mbt P04-US4② | 计划 |
| B-P06 stale-retry 命中 | — | — | **集成承载：P07**（spec DoD-2 映射口径；命中时对同一 `stale_evictions` +1） |
| B-P07 Call.cancel / 超时取消 | — | — | **集成承载：P08** |
| B-P08 租借/新建/LIFO/栈满容量 | T005、T006、T007、T008 | pool_test P04-US1①②③ + pool_wbtest P04-FR③ | 计划 |
| B-P09 驱逐显式入口与幂等 | T013、T015、T016 | pool_test P04-US3② + pool_wbtest P04-FR⑤⑦ + P04-E⑦ | 计划 |
| B-P10 并发租借正确性 | T017 | pool_test.mbt P04-US2① | 计划 |
| B-P11 长跑双证据守恒 | T018 | pool_longrun_test.mbt P04-LONGRUN①② | 计划 |
| B-P12 夹具可观测性扩展 | T002 | scripted_server_test.mbt P04-FIX①②③ | 计划 |

## FR-001～FR-018 覆盖核对表

| FR | 覆盖任务 | 核对口径 |
| --- | --- | --- |
| FR-001 租约独占 | T005/T006/T008 | 白盒 conn_id 互异 + borrowed 不交（不变量 1） |
| FR-002 归池判定（池侧谓词） | T006/T007/T009 | 未毒化 ∧ idle 未满 ⇔回池，否则 close |
| FR-003 不回池三路径 | T007/T009/T013/T014 | 毒化/栈满/超期逐分支断言 |
| FR-004 LIFO | T006 | conn_id 断言弹出同一实例 |
| FR-005 可周期执行 + 显式入口 + close 幂等 | T013/T014/T015 | 无常驻任务（E⑦）；同步入口；幂等断言 |
| FR-006 临界区无 IO/无 await | T004/T005（解锁后建连）+ T013（abort 防御） | 结构审 + R3 防御路径 |
| FR-007 计数可读与口径 | T007/T009/T013/T015 | Q3 口径钉死（FR⑦白盒） |
| FR-008 建连公开构造 | T005 | D13；`--deny-warn` 门零 deprecated |
| FR-009 双证据无泄漏 | T002/T018 | 外部 accepted_total + 内部三集合守恒 |
| FR-010 Connection: close 消费侧 | T011 | 桩管线判定；解析归 P05/P06（Q06） |
| FR-011 release 无状态参数 | T010 | 契约面审（contracts §1 无枚举） |
| FR-012 命名 snake_case | T019 | 冻结面审（零 camelCase） |
| FR-013 per_host_total 非硬上限 | T005/T017 | 并发租借不受计数约束（K=64 形态） |
| FR-014 Address 键隔离/规范化 | T003 | P04-E①～⑤ |
| FR-015 acquire 失败透传 | T005 | P04-E⑥（池状态零变化） |
| FR-016 冻结面对账 | T004/T019 | contracts §1 逐条 |
| FR-017 P07 兜底声明（非测试项） | — | spec 如实登记；不构造「取出即可用」断言 |
| FR-018 终结幂等 | T012 | P04-FR④ + P04-US4④ |

## SC-001～SC-007 覆盖核对表

| SC | 覆盖任务 | 缺项标注 |
| --- | --- | --- |
| SC-001 全绿 + 串号 0 | T017/T020 | 「全绿」口径随 DoD-1（C5：长跑显式执行） |
| SC-002 零泄漏双证据 | T018 + T020 对账 | 证据随 DoD-1 登记 |
| SC-003 复用命中率 | T006（LIFO）+ T018（长跑 ≥100 次） | 无 |
| SC-004 驱逐确定性/幂等 | T013/T015 | 无 |
| SC-005 毒化零回池 | T007/T009/T010/T012/T013 | 无 |
| SC-006 外部网络依赖 0 | 全部测试任务（P03 夹具 loopback） | 无 |
| SC-007 公开面零泄漏 | T004/T019 | 对账 contracts §1 |

## Dependencies & Execution Order

### Phase 依赖

- **Phase 1（Setup）**：无依赖，立即开始；T001 的静态计数式（160）是
  W09 工单给定的锚，动工时如遇数目漂移（如基线后其它包合入），以实测
  为准并在 baseline.md 记录新值与原因
- **Phase 2（Foundational）**：依赖 T001；T002 与 T003 可并行；T004 依赖
  T003（池用 Address）；**阻塞全部 US 任务**
- **Phase 3（US-1）**：依赖 Phase 2；是 MVP
- **Phase 4（US-4）→ Phase 5（US-3）→ Phase 6（US-2）**：顺序执行——
  US-4 按 owner 示踪弹顺序提前（W09 (iii)）；US-2 压轴（长跑守恒消费
  毒化/栈满/超期全部关闭路径在场后的三集合口径，research R7）
- **Phase 7（Polish）**：依赖全部 US 完成

### 并行机会

- T002 ∥ T003（不同文件）
- Phase 3 内 T005 → T006/T007 → T008 串行（同文件演进）；T008 白盒可与
  T006 并行（不同文件）
- T013/T014/T015 同文件（pool_wbtest/client.mbt）串行；T016 依赖 T013 的
  时钟注入设施
- T017 与 T018 同文件（pool_test/longrun 不同文件，可并行准备）

## Implementation Strategy

- **MVP**：Phase 1+2+3（US-1）交付后即得「可租借复用的最小池」，独立验证
  后可停
- **增量**：每 Phase 收尾跑一次分包双 target（quickstart §2），红不进
  下一 Phase
- **收口**：Phase 7 六门 + 对账 + DoD 勾选（长跑证据与 skip 核证记录
  一并归档）

## Notes

- **`-p` 只认包名**：`moon test -p hahh9527/moonhttp/client`；写目录路径
  （如 `-p src/client`）**跑 0 个测试却返回 exit 0**（假绿）——每条 `-p`
  命令后核对 `Total tests:` 非 0（quickstart §0）
- **测试命名**：`P04-US*`/`P04-E*`/`P04-FR*`/`P04-SC*`/`P04-LONGRUN*`/
  夹具侧 `P04-FIX*`（与 quickstart `-f` glob 一致，不得自创前缀）
- **先红后绿**：每任务元测试先失败再转绿；落笔即绿的护栏断言（T016、
  T010 契约面审）须在任务产出中显式标注「护栏/未红判据」，不得静默
  （003 T008/T016 先例）
- **禁 sleep 串联**：时间推进只用注入时钟（R2）；**禁 fd 计数**：泄漏
  判据只用双证据（Q04）；**禁响应头解析任务**：`Connection: close`
  判定归 P05/P06（Q06）
- **R3 纪律**：同步路径 `try_acquire` 失败即 abort，禁止静默跳过
- **[P] 语义**：不同文件、无未完成依赖；[Story] 标签对应 spec 用户故事
- 每任务或逻辑组完成后 commit；每个 Checkpoint 处停机验证（TDD 纪律，
  宪法 IV）
