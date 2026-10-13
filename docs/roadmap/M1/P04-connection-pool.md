# P04 连接池：租约、驱逐与毒化（L1）

> 里程碑：M1 性能核心 ｜ 前置依赖：P01、P03 ｜ 人力估计：~3 人日（核心+租约+驱逐 ~2，
> 池级测试 ~1；P10 另有基准验收）
> 来源：`proj-init-docs/okhttp-on-async-http/03-connection-pool/README.md` §3.1–§3.4/§7/§8
> 侵入性：非侵入（全部经 `Client::connect/close/skip_response_body` 公开 API）｜
> 建议特性 slug：`m1-p04-connection-pool`

## 功能描述（speckit 输入种子）

交付 moonhttp 的 HTTP/1.x 连接池——本全项目最大的性能杠杆（L1）：
按 **Address**（M1 为直连三元组 scheme/host/port）复用 `@http.Client` 连接，
提供 **Lease 租约**（一次 exchange 的独占句柄）、**LIFO 空闲栈归还**（热连接优先）、
**周期驱逐**（空闲超 keep_alive 关闭）与**毒化路径**（不可复用连接绝不回池）。
既有实测：新建连接 ≈10ms/请求 → 池化并发 ≈0.18–0.42ms（47–56×）；
M1 判据「≥20×」的量化验收在 P10，本包负责机制正确性。

## 范围

包含：

- `Address`（M1 直连形态：scheme/host/port，host 已剥 IPv6 括号；derive(Eq/Hash)）。
  `proxy`/`trust` 指纹字段不在 M1（README 差异 D3，随 M2/M3 扩展）。
- `ConnectionPool`：`max_idle`（默认 5）/`keep_alive`（默认 5min）可配置；
  `Mutex[PoolInner]`（临界区无 IO）；`idle : Map[Address, Array[IdleLease]]`
  LIFO 栈；`per_host_total` 与 `stale_evictions` 观测计数。
- `Lease`：`acquire(addr)`（命中弹出 / 未命中 `Client::connect` 新建）/`release()`
  归池判定（`body 已消费完 ∧ !poisoned ∧ idle 未满`，否则 close）/
  `poison()` 毒化标记。
- 驱逐：周期 `Timer` 扫描 `idle_since` 超 `keep_alive` 者关闭；`evictAll()` 幂等
  （`Client::close` 幂等，`client.mbt:142-151`）。
- 归池前提的执行侧钩子：`Connection: close` 响应头判定接口（读响应头后检查，
  命中则读完 body 后 close 不回池——管线侧调用点在 P05/P06 落地）。

非目标（显式排除，README 差异 D3）：

- 代理（ProxyConfig/CONNECT 隧道包装/代理连接池）与 http-over-proxy
  absolute-form——归 M2；
- DNS 缓存（L4/侵入点 I2）——归 M2 上游 PR 包；
- Route 级选择器（Route 不进池键；Happy Eyeballs 藏于 `connect_to_host` 内部，
  路由重试语义由 P07 的整体重试覆盖）；
- TCP keepalive 透传（侵入点 I6，OkHttp 默认亦不开）；
- TLS 会话复用（I11）；空闲连接主动探测（OkHttp 亦无，靠 stale-retry 兜底）；
- HTTP/2 多路复用（M6）。

## 用户故事种子

### US-1 租借与归还（P1）

作为执行管线（P05），我用 `pool.acquire(addr)` 拿到独占 Lease，一次 exchange
结束后 `release()`：可复用则回空闲栈，不可复用（毒化/栈满）则关闭。

**独立测试**：直接以 `@http.Client` 原语 + Lease 手动驱动请求（不经 P05）。

**验收场景**：

1. Given 空池，When acquire，Then 新建连接、`per_host_total` 递增。
2. Given 已 release 的干净 Lease，When 再次 acquire 同 Address，Then 弹出同一连接
   实例（LIFO）、无新建。
3. Given `release` 时 idle 栈已满（max_idle），Then 连接被 close 不入栈。

### US-2 并发租借正确性（P1）

作为使用者，我对同一 host 并发 acquire/release 多条连接，任意交错下无串响应、
无重复出租同一连接。

**验收场景**：

1. Given P03 echo 夹具 + 池（K=8），When 并发 100 个「acquire→请求→校验回显
   id→release」，Then 全部请求 body 与自身 id 匹配（串号检测为零）。
2. Given 长跑 ≥10k 请求，Then idle 数守恒（借出+空闲 = 总数）、（native）fd 数
   不随请求数增长（无泄漏）。

### US-3 驱逐与 evictAll（P1）

作为使用者，空闲连接在 keep_alive 到期后被关闭；`evictAll()` 立即清空且可重复调用。

**验收场景**：

1. Given keep_alive=1s 的池与 2 条空闲连接，When 等待超期 + 驱逐周期，
   Then idle 清空、连接已关闭。
2. Given 任意状态，When 连续 `evictAll()` 两次，Then 无错误、idle 为空（幂等）。

### US-4 毒化路径（P2）

作为管线/重试/取消的下游（P05/P07/P08），我对不可复用连接标记毒化：
release 时绝不回池、直接 close。

**验收场景**：

1. Given 毒化 Lease，When release，Then 连接关闭、idle 不增长。
2. Given `Connection: close` 判定接口命中，When 管线释放，Then 不回池
   （以桩管线或 P05 集成测试覆盖）。
3. Given 响应体未消费完即 release（残数据），Then 不回池。

（stale-retry 命中与超时取消两行的端到端验收分别落在 P07/P08。）

## 边界用例

- 同 host 不同端口/scheme → 不同 Address（键隔离）；host 大小写规范化后同键
  （依赖 P01 HttpUrl 规范化）；
- acquire 新建连接失败（P03 注入 connect 拒绝）→ 错误透传、池状态不变；
- 驱逐 Timer 与 acquire/release 竞争（同一空闲连接恰在驱逐瞬间被取出——不得
  double-close 崩溃，close 幂等兜底）；
- 池在无任何活动时 Timer 空转成本（设计上避免忙轮询）。

## 需求种子

- **FR-001** 同一 Lease 期间连接 MUST 独占（@http.Client 单请求在途状态机前提）。
- **FR-002** release MUST 满足「body 已消费完 ∧ 未毒化 ∧ idle 未满」才回池。
- **FR-003** 毒化/超期/栈满路径 MUST 关闭连接，绝不回池。
- **FR-004** acquire MUST LIFO 弹出（最热连接优先）。
- **FR-005** 驱逐 MUST 周期执行且 close 幂等（重复关闭安全）。
- **FR-006** 池操作临界区 MUST 无 IO（宪法「IO 时不持锁」）。
- **FR-007** `stale_evictions`/`per_host_total` 计数 MUST 可读（P10/未来 06 观测）。

## 关键设计要点

- 结构照 `03 §3.2`：`ConnectionPool{max_idle, keep_alive, inner : Mutex[PoolInner]}`；
  `IdleLease{conn, idle_since}`；`Lease{addr, conn, pool, poisoned}`。
- 独占语义：租约期间连接只属于当前 exchange，池无需 per-connection 锁；
  Mutex 仅保护 idle 栈取放。
- 被动检测为主：不主动探测空闲连接死活（OkHttp 同款），长闲连接被服务端静默
  关闭由 P07 stale-retry 兜底——**池化正确性依赖该闭环**，P07 未落地前长闲场景
  错误率上升属已知中间状态（集成顺序上 P07 紧随）。
- 驱逐 Timer 生命周期：挂在池自身的 TaskGroup/独立句柄，进程内常驻；
  句柄形态在 plan 定（澄清种子 C2）。

## 侵入性与宪法合规

- 非侵入：`Client::connect`/`close`/`skip_response_body` 全公开。
- 宪法 II：本包是「已实测杠杆必须保持不回归」的核心载体——P10 门禁直接挂钩；
  池自身开销须亚微秒级（Map 查找+栈弹出+Mutex 取放）。
- 宪法 V：js 上池无意义（fetch 连接由浏览器管理），退化为空实现/直通——
  归 P05/P09 的 js 路径处理，本包在 js 仅要求编译通过。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同源逻辑；wasm 宿主 socket 的 RST 等语义差异由 P03/P07 测试覆盖 |
| js | ⭕ | 池层退化为空实现（Lease=Client 直通），仅编译/空跑语义 |
| wasm-gc | ❌ | 上游 runtime 缺口 |

## 性能影响

L1 杠杆本体：churn ≈10ms → 复用 0.42ms → 池化并发 0.18ms（47–56×，round2）。
量化验收（≥20× 门槛、K∈{1,4,16,64} 矩阵、RSS 曲线）在 P10 统一执行——本包测试
只断言机制正确性与无泄漏，不断言延迟数字（避免基准抖动侵蚀单元测试稳定性）。

## 测试方案

- US-1–US-4 场景全部基于 P03 夹具（echo/延迟/故障注入），native+wasm 双绿。
- 长跑泄漏用例（≥10k 请求）以独立标记（如 `@bench`/长测标签）与常规测试分离，
  避免拖慢 CI——具体机制 plan 定。
- fd 计数断言仅 native（平台相关，wasm 以池内计数守恒代替）。

## 澄清问题种子

- **C1** `Connection: close` 判定接口形状（池侧提供谓词 vs 管线自查响应头）。
- **C2** 驱逐 Timer 的宿主与生命周期（独立 TaskGroup / 池内句柄；测试模式下
  手动触发清扫的口子）。
- **C3** Mutex 的取舍：事件循环单线程下是否退化为普通字段 + 文档约定
  （原文为「防 re-entrancy/未来多线程」保留 Mutex——遵原文，但确认无性能噪点）。
- **C4** max_idle/keep_alive 的配置面（pool 构造参数 vs HttpClient builder 透传，
  与 P08 的 builder 设计对齐）。
- **C5** 长跑/泄漏用例与常规 `moon test` 的隔离机制。

## 验收判据（包级 DoD）

1. US-1–US-4 验收场景测试全绿（native/wasm 双 target）。
2. 毒化路径表（03 §3.4 全部行）在本包或集成包（P05/P07/P08）中逐行有对应用例，
   本包 DoD 范围内至少覆盖「毒化标记/栈满/超期/Connection: close/残 body」五行。
3. `moon info && moon fmt` 干净；`.mbti` 冻结 Address/ConnectionPool/Lease 公开面。

## 参考

- `03-connection-pool/README.md` §3.1（Address/Route）、§3.2（结构与租约）、
  §3.3（驱逐）、§3.4（毒化表）、§6（量化）、§8（测试方案）。
- `14-performance/README.md` §1（round1–3 实测数据）、§2 L1。
- 下游引用方：P05（execute 集成）、P07（stale 毒化）、P10（基准门禁）。
