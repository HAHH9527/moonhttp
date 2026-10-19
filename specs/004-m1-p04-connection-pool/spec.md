# Feature Specification: 连接池：租约、驱逐与毒化（M1-P04）

**Feature Branch**: `004-m1-p04-connection-pool`（分支已存在并在使用，
特性目录与分支同名，specify 节点不建分支）

**Created**: 2026-10-19

**Status**: Draft

**Input**: User description: "功能描述 = 仓库文件
docs/roadmap/M1/P04-connection-pool.md 的全文（speckit 输入种子，唯一功能
描述输入）" ＋ owner 已裁决既定前提 P1–P10（2026-10-19，落点见
「既定裁决前提」；clarify 阶段不得重开为待议问题）。

## Clarifications

### Session 2026-10-19

- Q: `ConnectionPool` 的 `max_idle` 与 `keep_alive` 在本包（P04）以什么
  形式暴露为可配置项？（种子 C4）→ A: 仅以 `ConnectionPool` 构造参数
  暴露（缺省 5 / 5min）；builder 透传归 P08（owner 2026-10-19 裁决；
  P04 公开面不引入 builder 形态，`.mbti` 冻结面随之收窄）。
- Q: 长跑/泄漏用例（native ≥10k 请求级、wasm/moonrun 按吞吐分档降额）
  是否默认排除在常规 `moon test` 质量门（六门）之外？（种子 C5）→ A:
  默认排除——常规六门「全绿」不含长跑；长跑以显式命令/标记单独执行，
  通过证据单独登记进包级 DoD（owner 2026-10-19 裁决；具体隔离机制归
  plan）。
- Q: `stale_evictions` 计数器在本包统计哪些「关闭不回池」事件？→ A:
  仅计超期剔除——`evict_expired()` 与 acquire/release 惰性剔除各 +1；
  `evict_all()` 不计（可能关闭未超期连接）；毒化/栈满不计（US-4 以
  idle 不增长断言）（owner 2026-10-19 裁决；相对 03 §3.4 原义的有意
  语义扩展与 P07 归属见 FR-007 注记）。
- Q: 池内部状态（空闲栈与计数）在事件循环单线程模型下，是否保留互斥锁
  保护？（种子 C3）→ A: 保留——遵 03 §3.2 与种子原文，防 re-entrancy、
  为未来多线程留形；性能噪点由 P10 基准证实/证伪，退化形态不在本包
  范围（owner 2026-10-19 裁决）。
- Q: 同一 Lease 的 `release()` 被调用第二次（或 release 之后又调用
  `poison()`）时，池应表现出什么可判定行为？→ A: release 幂等——首次
  调用生效（按归池判定回池或关闭），后续 release/poison 均为 no-op，
  不重复入栈、不破坏空闲栈守恒（owner 2026-10-19 裁决；内部「已释放」
  标记属实现细节、归 plan，不进公开面）。

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测——只实现其中一条也应产出可用价值。
  优先级继承种子文件：US-1/US-2/US-3 为 P1，US-4 为 P2。
-->

### User Story 1 - 租借与归还（Priority: P1）

作为执行管线（P05），我用 `pool.acquire(addr)` 拿到独占 Lease，一次
exchange 结束后 `release()`：可复用则回空闲栈，不可复用（毒化/栈满）则
关闭。

**Why this priority**: 池的核心价值路径——租借复用直接兑现 L1 杠杆
（单连接顺序复用 ≈24× 实测臂）；后续全部故事都建立在租借语义之上。

**Independent Test**: 直接以 `@http.Client` 原语 + Lease 手动驱动请求，
不经 P05（种子独立测试口径）。

**Acceptance Scenarios**:

1. **Given** 空池，**When** acquire，**Then** 新建连接且 `per_host_total`
   递增（可观测计数，FR-007）。
2. **Given** 已 release 的干净 Lease，**When** 再次 acquire 同 Address，
   **Then** 弹出同一连接实例（LIFO）且无新建（`per_host_total` 不变）。
3. **Given** release 时 idle 栈已满（max_idle），**When** release，
   **Then** 连接被 close、不入栈（close 幂等，重复关闭安全）。

---

### User Story 2 - 并发租借正确性（Priority: P1）

作为使用者，我对同一 host 并发 acquire/release 多条连接，任意交错下无串
响应、无重复出租同一连接。

**Why this priority**: 串响应/重复出租是池化最恶性缺陷；P05 执行管线的
正确性直接依赖本条，且是 P10 基准门禁可信度的前提。

**Independent Test**: 以 P03 echo 夹具 + 池并发驱动（不经 P05），回显 id
逐一比对即可判定串号。

**Acceptance Scenarios**:

1. **Given** P03 echo 夹具 + 池（K=8），**When** 并发 100 个「acquire→
   请求→校验回显 id→release」，**Then** 全部请求 body 与自身 id 匹配
   （串号检测为零）。
2. **Given** 长跑（native ≥10k 请求；wasm/moonrun 按吞吐分档降额，实测
   见 specs/003-m1-p03-test-fixtures/t004-record.md），**Then** idle 数
   守恒（借出+空闲 = 总数）且无泄漏按双证据断言：外部——P03 夹具累计
   accept 连接数 == 池内累计新建连接数；内部——池侧 `conn_id` 集合基数
   守恒（借出+空闲+已关 = 累计新建）（裁决 Q04；外部证据依赖 FR-009 的
   夹具可观测性扩展）。

---

### User Story 3 - 驱逐与 evict_all（Priority: P1）

作为使用者，空闲连接在 keep_alive 到期后由**显式驱逐入口**
`evict_expired()` 或后续池操作（acquire/release 顺手剔除）关闭——池无
常驻任务，不会自动清扫；`evict_all()` 立即清空且可重复调用。

**Why this priority**: 驱逐决定空闲资源的回收与 keep_alive 语义；同时是
「池不养常驻任务」这一裁决形态（D15）的主要可验收面。

**Independent Test**: 以可注入时钟驱动超期后直接调用
`evict_expired()`/`evict_all()` 断言（不经管线，种子独立测试口径）。

**Acceptance Scenarios**:

1. **Given** keep_alive=1s 的池与 2 条空闲连接，**When** 推进可注入时钟
   过 keep_alive 并调用 `evict_expired()`，**Then** 剔除 2 条
   （`stale_evictions` 递增可观测，FR-007）、idle 清空、连接已关闭。
2. **Given** 任意状态，**When** 连续 `evict_all()` 两次，**Then** 无
   错误、idle 为空（幂等）。

---

### User Story 4 - 毒化路径（Priority: P2）

作为管线/重试/取消的下游（P05/P07/P08），我对不可复用连接标记毒化：
release 时绝不回池、直接 close。

**Why this priority**: 毒化是复用正确性的安全网，但可后置于租借主干——
US-1/US-2/US-3 已构成可用的最小池。

**Independent Test**: 以原生 `@http.Client` + Lease 手动构造毒化场景
（毒化标记/栈满/残 body 契约），不经管线断言归池行为。

**Acceptance Scenarios**:

1. **Given** 毒化 Lease，**When** release，**Then** 连接关闭、idle 不
   增长。
2. **Given** `Connection: close` 判定命中（管线侧判定后调用 poison()，
   判定接口归属见 FR-010），**When** 管线释放，**Then** 不回池（以桩
   管线或 P05 集成测试覆盖）。
3. **Given** 响应体未消费完的 Lease（按调用方契约先行毒化，见 FR-011），
   **When** release，**Then** 不回池。
4. **Given** 已 release 的 Lease，**When** 再次 release（或先 poison 再
   release），**Then** 均为 no-op——不重复入栈、不二次关闭，空闲栈守恒
   保持（借出+空闲+已关 ＝ 累计新建；FR-018）。

（stale-retry 命中与超时取消两行的端到端验收分别落在 P07/P08，映射口径
见包级 DoD-2。）

---

### Edge Cases

- 同 host 不同端口/scheme → 不同 Address（键隔离）；host 大小写规范化后
  同键（依赖 P01 HttpUrl 规范化；FR-014）。
- acquire 新建连接失败（P03 注入 connect 拒绝）→ 错误透传、池状态不变
  （无半租约残留；FR-015）。
- 驱逐与 acquire/release 竞争：惰性 + 显式口径下该竞态在结构上不存在——
  剔除与弹出同处一个互斥临界区、临界区内无 await，无需专门构造时序用例；
  连接关闭的幂等性（重复关闭安全）降为兜底保障（FR-005）。
- 池在无任何活动时零空转成本（无常驻任务，无调用即无驱逐）；「不得忙
  轮询」的要求由调用方侧承担——P05/P09/P10 自设的扫描周期不得形成忙
  轮询（README 差异 D15）。
- 长闲连接被服务端静默关闭：本池不主动探测（OkHttp 同款），由 P07
  stale-retry 兜底——P07 未落地前长闲场景错误率上升属已知中间状态，
  本 spec 不将其写成池可独立保证的性质（FR-017）。
- 同一 Lease 重复 release / 释放后毒化：release 幂等（首次生效，后续
  no-op），空闲栈守恒不被破坏（FR-018）。

## Requirements *(mandatory)*

### 既定裁决前提（owner 2026-10-19，clarify 阶段不得重开）

以下十条为已生效裁决，作为本 spec 的约束性前提登记；差异登记锚点见
`docs/roadmap/M1/README.md` 第 3 节（D1–D15）：

- **P1（差异 D13）建连方式**：池只能经公开构造器 `Client::Client(uri)`
  建连（已复核 `client.mbt:115` 的 `#alias(new, deprecated)` 与 `:117`
  的构造器签名）；上游无公开 `Client::connect`，`Client::new` 触发弃用
  警告、`--deny-warn` 质量门判红。
- **P2（差异 D15）驱逐形态**：惰性 + 显式。池不养常驻任务，只暴露同步
  入口 `evict_expired()`/`evict_all()`；超期判定为 `now` 的纯函数
  （空闲起点与 keep_alive 比较）；周期扫描由调用方（P05/P09/P10）在自己
  task group 里 `spawn_bg(no_wait=true)` 驱动。
- **P3（裁决 Q04）无泄漏判据**：双证据并列——外部：夹具累计 accept 连接
  数 == 池内新建连接数；内部：池侧 `conn_id` 集合基数守恒。native/wasm
  同用，长跑规模按 target 分档；原 fd 计数不可断言（`@http.Client` 公开
  面无 fd/shutdown，自写 FFI 探测违反宪法 I）。
- **P4（承种子澄清 C1）`Connection: close` 归属**：池只认 `poison()`；
  判定接口以「文档约定 + P05 集成用例桩」的形式留在 spec，P04 不实现
  响应头解析（种子已把管线调用点划给 P05/P06）。
- **P5（残 body 谓词）**：不新增公开枚举、`release` 不带状态参数；残
  body 由调用方先 `skip_response_body()` 或按默认毒化契约处理（`Client`
  在途状态字段私有，池侧无法内省）。
- **P6（命名与占位）**：公开入口命名 `evict_all`/`evict_expired`（本仓
  `.mbti` 零 camelCase）；`src/client/placeholder` 本包不删（删除留给
  implement 收口片，避免基线记账被搅动）。
- **P7（观测语义）**：`per_host_total` 是观测计数、不是硬上限；与 OkHttp
  Dispatcher 每主机并发上限的有意差异显式记录（P10 需要 K=64 的并发
  形态）。
- **P8（target 口径）**：native + wasm 双绿（宪法 V）；js 标**未验证**
  （差异 D14，依 D9 挂欠账 F9、随 M5 收口）；wasm-gc 不支持。种子
  target 矩阵的 ✅ 指 wasm，非 wasm-gc。
- **P9（夹具扩展）**：P03 夹具可观测性扩展（累计 accept 计数 / 每连接
  请求数 / per-route 次序脚本）纳入本包范围、实现列 implement 首片；
  本 spec 把「依赖夹具新增可观测能力」写成功能前提（FR-009），不假设
  现成夹具已具备。
- **P10（毒化表映射）**：03 §3.4 五行与本包自列五行的映射口径原样进入
  包级 DoD-2；每一行落「本包用例 / 集成包用例（P05/P07/P08）/ 不适用」
  三者之一。

### 范围

**包含**：

- `Address`：M1 直连三元组 scheme/host/port（host 剥 IPv6 括号、大小写
  规范化；`proxy`/`trust` 指纹不在 M1，差异 D3）。
- `ConnectionPool`：`max_idle`（默认 5）/`keep_alive`（默认 5min）可
  配置——配置面为池构造参数（owner 2026-10-19 裁决，见 Clarifications；
  builder 透传归 P08）；空闲栈按 Address 分桶、LIFO 取放；
  `per_host_total` 与 `stale_evictions` 观测计数（FR-013 的观测语义）。
- `Lease` 租约：acquire / release / poison() 生命周期与归池判定。
- 驱逐：惰性 + 显式（P2/差异 D15），含 `evict_expired()`/`evict_all()`
  两个同步显式入口。
- P03 夹具可观测性扩展（P9 裁决）：累计 accept 计数、每连接请求数、
  per-route 次序脚本——实现列 implement 首片。
- `Connection: close` 判定接口的文档约定（P4：池不实现响应头解析）。

**非目标（显式排除，含归属，clarify 不复议）**：

- 代理（ProxyConfig/CONNECT 隧道包装/代理连接池）与 http-over-proxy
  absolute-form——归 M2；
- DNS 缓存（L4/侵入点 I2）——归 M2 上游 PR 包；
- Route 级选择器（Route 不进池键；Happy Eyeballs 藏于上游
  `connect_to_host` 内部，路由重试语义由 P07 的整体重试覆盖）；
- TCP keepalive 透传（侵入点 I6，OkHttp 默认亦不开）；
- TLS 会话复用（I11）；
- 空闲连接主动探测（OkHttp 亦无，靠 stale-retry 兜底）；
- HTTP/2 多路复用——归 M6；
- 常驻/自动驱逐任务——裁决 D15 否决（前提 P2），池 MUST NOT 提供。

### Functional Requirements

- **FR-001**（种子）同一 Lease 期间连接 MUST 独占：租约未归还前，同一
  连接 MUST NOT 被再次出租（底层 Client 单请求在途状态机的前提）。
- **FR-002**（种子；池侧可判定谓词按 P5 校准）release 归池判定：池侧
  可判定谓词为「未毒化 ∧ idle 未满」——满足则回空闲栈，否则 close。
  「body 已消费完」是调用方契约（P5），不由池在 release 时检测。
- **FR-003**（种子）毒化/超期/栈满三条路径 MUST 关闭连接、绝不回池。
- **FR-004**（种子）acquire MUST 按 LIFO 弹出（最热连接优先）。
- **FR-005**（种子；差异 D15）驱逐 MUST 可周期执行（周期由调用方驱动），
  MUST 提供显式同步入口 `evict_expired()`/`evict_all()`；池 MUST NOT
  启动任何常驻扫描任务；连接关闭 MUST 幂等（重复关闭安全）。
- **FR-006**（种子；C3 裁决见 Clarifications）池操作临界区 MUST 无 IO
  （宪法「IO 时不持锁」）；内部状态以互斥锁保护——遵 03 §3.2 原文保留
  （防 re-entrancy、为未来多线程留形），性能噪点由 P10 基准证实/证伪，
  退化形态不在本包范围。
- **FR-007**（种子；计数口径 2026-10-19 裁决，见 Clarifications）
  `stale_evictions`/`per_host_total` 计数 MUST 可读（用户故事验收与
  P10/未来 06 观测的判据面）。`stale_evictions` MUST 仅计超期剔除：
  `evict_expired()` 与 acquire/release 惰性剔除各 +1；`evict_all()` 的
  关闭与毒化/栈满关闭 MUST NOT 计入（毒化/栈满路径以 idle 不增长断言
  观测）。语义偏移注记：本口径把「stale」相对 03 §3.4 原文（仅
  stale-retry 命中 +1，`03-connection-pool/README.md:102`）有意扩展为
  「陈旧连接家族 ＝ 超期剔除 ＋ P07 stale-retry 命中」——因 stale-retry
  归 P07 承载，本包内该家族当前只有超期剔除；P07 落地时其命中行照
  03 §3.4 对同一计数器 +1（集成归属见 DoD-2 映射口径）。
- **FR-008**（P1/差异 D13）建连 MUST 只经公开构造器
  `Client::Client(uri)`；MUST NOT 依赖上游非公开 API 或 deprecated 别名
  （`--deny-warn` 质量门下零警告编译）。
- **FR-009**（P3/Q04 + P9）无泄漏 MUST 以双证据断言：外部——P03 夹具
  累计 accept 连接数 == 池内累计新建连接数（服务端侧看不到多余连接）；
  内部——池侧 `conn_id` 集合基数守恒（借出+空闲+已关 = 累计新建）。
  外部证据依赖的夹具累计 accept 计数属本包交付范围（P9，implement
  首片）。MUST NOT 以 fd 句柄计数为判据（公开面无 fd，FFI 探测违反
  宪法 I）。
- **FR-010**（P4）`Connection: close` 响应头判定不属本包实现范围：池侧
  MUST 只消费 `poison()` 标记；判定接口以文档约定记录，由 P05/P06 在
  管线侧落地并以集成用例桩覆盖（US-4 场景 2）。
- **FR-011**（P5）`release` MUST NOT 携带状态参数、MUST NOT 为「残
  body」新增公开枚举；未消费完响应体的连接由调用方先
  `skip_response_body()` 或先行 `poison()`（默认毒化契约由 P05 集成
  承载——池侧对在途状态不可内省，如实登记为能力边界）。
- **FR-012**（P6）公开面命名 MUST 遵守本仓 `.mbti` 命名惯例（零
  camelCase）：驱逐入口为 `evict_expired`/`evict_all`。
- **FR-013**（P7）`per_host_total` MUST 为观测计数、MUST NOT 构成并发
  硬上限：同 Address 的并发租借数不受其约束（P10 的 K=64 形态依赖此
  语义）；与 OkHttp Dispatcher 每主机上限的有意差异在此显式记录
  （宪法 III）。
- **FR-014**（边界/键隔离）Address MUST 按「规范化后的 scheme/host/
  port」等值判定：同 host 不同端口或不同 scheme MUST 为不同键（互不
  租借）；host 大小写差异 MUST 规范化为同键（规范化语义以 P01 冻结面
  为准）。
- **FR-015**（边界）acquire 新建连接失败（如 P03 注入 connect 拒绝）
  MUST 将错误透传给调用方，且池状态 MUST 保持不变（无半租约、不污染
  空闲栈、计数不虚增）。
- **FR-016**（.mbti 冻结面，可验收）Address/ConnectionPool/Lease 三者
  的公开面 MUST 与本 spec「Key Entities」记录一致并冻结：实现完成后
  `.mbti` 审视（宪法 VI）以其为对账面，计划外公开项为零。
- **FR-017**（关键中间状态，如实登记）本包 MUST NOT 声称独立保证「取出
  的空闲连接一定可用」：长闲连接被服务端静默关闭由 P07 stale-retry
  兜底，P07 未落地前长闲场景错误率上升属已知中间状态（集成顺序上
  P07 紧随）。
- **FR-018**（2026-10-19 裁决，见 Clarifications）Lease 终结幂等：同一
  Lease 的 `release()` 首次调用生效（按 FR-002 归池判定回池或关闭），
  其后重复 `release()` 或 `poison()` MUST 为 no-op——MUST NOT 重复入
  空闲栈、MUST NOT 二次关闭、MUST NOT 破坏空闲栈守恒（借出+空闲+已关
  ＝ 累计新建）；内部「已释放」标记属实现细节（归 plan），不进公开面。

### Key Entities

- **Address**：池键。M1 为直连三元组 scheme/host/port（host 已剥 IPv6
  括号、大小写规范化）；等值语义见 FR-014；`proxy`/`trust` 指纹不在 M1
  （差异 D3，随 M2/M3 扩展）。
- **ConnectionPool**：按 Address 分桶的 LIFO 空闲栈 + 配置（构造参数
  `max_idle` 默认 5、`keep_alive` 默认 5min；builder 透传归 P08）+
  观测计数（`per_host_total`、`stale_evictions`）；驱逐为惰性 + 显式，
  无任何常驻任务。
- **Lease**：一次 exchange 的独占句柄，带毒化标记；acquire（命中弹出 /
  未命中经 `Client::Client(uri)` 新建）、release（归池判定）、poison()
  是其公开生命周期；终结后重复 release/poison 为 no-op（FR-018）。
- **IdleLease**：空闲栈条目 = 连接 + 空闲起点时刻；超期判定为「当前
  时刻的纯函数」（起点与 keep_alive 比较，无内部时钟副作用）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1–US-4 全部验收场景测试全绿，native 与 wasm 双 target
  （宪法 IV/V；「全绿」口径随 DoD-1——裁决 C5：长跑用例显式执行、
  单独登记，不在默认六门内）；并发串号为 0（US-2 场景 1 的 100 请求
  回显全部与自身 id 匹配）。
- **SC-002**: 零泄漏（双证据、native/wasm 同用）——长跑结束后：夹具
  累计 accept 连接数 == 池内累计新建连接数；池侧 conn_id 基数满足
  「借出+空闲+已关 = 累计新建」。两证据误差均为 0。
- **SC-003**: 复用命中率可证——同 Address 连续 acquire/release ≥100
  次，池内累计新建连接数恰为 1（`per_host_total` == 1，LIFO 命中，
  无多余连接）。
- **SC-004**: 驱逐确定性——时钟推进过 keep_alive 后调用
  `evict_expired()`：超期空闲连接 100% 剔除（`stale_evictions` 递增量
  == 超期条数）、未超期连接 0 误剔；`evict_all()`/`evict_expired()`
  重复调用 0 错误且状态不变（幂等）。
- **SC-005**: 毒化零回池——毒化/栈满/超期/残 body（按调用方契约）任一
  路径关闭的连接，在其后全部 acquire 中被再次出租的次数为 0。
- **SC-006**: 外部网络依赖为 0——全部测试仅访问 P03 本地夹具
  （loopback），断网环境全套测试仍全绿。
- **SC-007**: 公开面零泄漏——实现完成后 `.mbti` 审视（宪法 VI）显示
  Address/ConnectionPool/Lease 公开面与本 spec「Key Entities」一致，
  计划外公开项为 0（对账面 FR-016）。

## Assumptions

- 时钟确定性：US-3 场景 1 依赖「可注入时钟」推进 keep_alive 到期；注入
  形态（构造助手/测试钩子）由 plan 裁决，本 spec 只约定「超期判定可被
  测试确定性地驱动到任一时刻」。
- 长跑隔离的具体机制（标记/目录/过滤形态）与 Lease「已释放」标记的
  内部形态归 plan（行为契约已裁决，见 Clarifications）。
- 池自身开销亚微秒级（Map 查找+栈弹出+互斥取放）为设计约束（宪法 II）；
  量化验收（≥20× 门槛、K∈{1,4,16,64} 矩阵、RSS 曲线）归 P10，本包测试
  不断言延迟数字（避免基准抖动侵蚀单元测试稳定性）。
- `src/client/placeholder` 本包不删除（P6）：删除动作留给 implement
  收口片，避免基线 160 的记账被搅动。
- `max_idle=5` / `keep_alive=5min` 为种子默认值；配置入口已裁决为池
  构造参数（2026-10-19，见 Clarifications），builder 透传归 P08。
- 周期扫描的宿主（P05/P09/P10 各自 task group）不在本包交付面内；本包
  仅保证被驱动的显式入口存在且语义可判定（P2）。

## 宪法合规口径（Target 矩阵 / 性能影响 / 测试方案）

**Target 矩阵（宪法 V；P8 口径）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 质量门双绿 target；同源逻辑，wasm 宿主 socket 语义差异由 P03/P07 测试覆盖（本行 ✅ 指 wasm，非 wasm-gc） |
| js | ⭕ | **未验证**（差异 D14/D9：六门从不跑 js，「仅编译通过」不可由门禁兑现；挂欠账 F9，随 M5 收口）。池层退化为空实现/直通（fetch 连接由浏览器管理），js 路径处理归 P05/P09 |
| wasm-gc | ❌ | 上游 runtime 缺口（差异 D9） |

**性能影响（按臂分述）**：L1 杠杆本体（03 §6 分臂）——新建 ≈10ms/请求
（1× 基线）→ 单连接顺序复用 415–431µs（≈24×）与池 K=16 并发 178–196µs
（47–56×，round2）是**两条臂**；「≥20×」量化验收在 P10 统一执行。本包
测试只断言机制正确性与无泄漏，不断言延迟数字。

**测试方案**：US-1–US-4 场景全部基于 P03 夹具（echo/延迟/故障注入），
native+wasm 双绿；长跑泄漏用例**默认排除在常规六门外**（裁决 C5，见
Clarifications），以显式命令/标记单独执行、通过证据单独登记进包级
DoD——具体隔离机制（标记/目录/过滤形态）归 plan；泄漏判据为双证据
（FR-009）。

## 包级 DoD（验收判据）

1. US-1–US-4 验收场景测试全绿（native/wasm 双 target）。「全绿」口径
   （裁决 C5，见 Clarifications）：常规子集（默认六门）全绿；长跑/
   泄漏用例（US-2 场景 2）默认排除在六门之外，以显式命令单独执行并
   登记通过证据——两部分合为 DoD-1 完成判据。
2. 毒化路径表（03 §3.4 全部行）在本包或集成包（P05/P07/P08）中逐行有
   对应用例，本包 DoD 范围内至少覆盖「毒化标记/栈满/超期/
   Connection: close/残 body」五行。**映射口径**：03 §3.4 五行与上述
   五项非同表换名，对应为——「协议错误（BadRequest 等）」↔ 毒化标记
   （poison() 的原型触发源：解析失败即毒化）、「`Connection: close`
   响应头」↔ Connection: close 判定、「响应体未消费完即弃」↔ 残 body
   （后两组同名语义直对应）；「stale-retry 命中（02）」↔ P07、
   「Call.cancel / 超时取消」↔ P08（集成包承载）；本包自列的「栈满」
   「超期」为池容量/驱逐侧「不回池即 close」家族（03 §3.2/§3.3 的
   推论，不在 §3.4 毒化表内）——补此映射闭合「逐行」口径。每一行均落
   「本包用例 / 集成包用例（P05/P07/P08）/ 不适用」三者之一（裁决
   P10）。
3. `moon info && moon fmt` 干净；`.mbti` 冻结 Address/ConnectionPool/
   Lease 公开面（FR-016/SC-007）。
4. P03 夹具可观测性扩展（累计 accept 计数 / 每连接请求数 / per-route
   次序脚本）随本包首片交付并有自证元测试（P9 裁决）。

## 待澄清项（种子 C1–C5 已全部裁决，无遗留）

- **C1**（已裁决，承 P4）`Connection: close` 判定接口形状：管线自查
  响应头（池只认 poison()；判定以文档约定 + P05 集成用例桩承载）。
- **C2**（已裁决，owner 2026-10-19，差异 D15）驱逐驱动形态为惰性 +
  显式；原 C2 想要的「测试模式下手动触发清扫的口子」正是
  `evict_expired()`。
- **C3**（已裁决，owner 2026-10-19，见 Clarifications）池内部状态保留
  互斥锁保护（遵 03 §3.2 原文）；性能噪点由 P10 基准证实/证伪，退化
  形态不在本包范围。
- **C4**（已裁决，owner 2026-10-19，见 Clarifications Session
  2026-10-19）`max_idle`/`keep_alive` 仅以池构造参数暴露（缺省
  5 / 5min）；builder 透传归 P08。
- **C5**（已裁决，owner 2026-10-19，见 Clarifications）长跑/泄漏用例
  默认排除在常规六门外，显式执行并单独登记证据；具体隔离机制归 plan。

## 参考

- `docs/roadmap/M1/P04-connection-pool.md`（本包唯一规格种子，已经
  W02/W04/W04b 三轮校正定稿）
- `docs/roadmap/M1/README.md` 第 3 节差异表（D3/D9/D13/D14/D15；本
  spec 既定裁决前提 P1–P10 的登记处）
- `docs/roadmap/deferred-items/deferred-items-m1.md`（F9 js 欠账等
  跨里程碑跟踪）
- `proj-init-docs/okhttp-on-async-http/03-connection-pool/README.md`
  §3.1–§3.4（Address/结构与租约/驱逐/毒化表）、§6（量化）、§8（测试
  方案）
- `proj-init-docs/okhttp-on-async-http/14-performance/README.md` §1/§2
  （round1–3 实测、L1 杠杆）
- `.mooncakes/moonbitlang/async/src/http/client.mbt:115/:117`（建连
  公开面取证：deprecated 别名与 `Client::Client` 构造器）
- `specs/003-m1-p03-test-fixtures/spec.md`（P03 夹具冻结面与行为清单：
  echo B-04、故障注入 B-09/B-10、帧形态 B-05）
- `.specify/memory/constitution.md`（原则 I/II/III/IV/V/VII）
