# Research：P04 连接池（M1-P04）

> 特性：specs/004-m1-p04-connection-pool ｜ 分支：004-m1-p04-connection-pool ｜
> 日期：2026-10-19
> 规格依据：spec.md（含 Clarifications Session 2026-10-19 五问与既定裁决前提
> P1–P10）；宪法 v1.2.0；治理差异 docs/roadmap/M1/README.md 第 3 节 D1–D15。
> 行号锚点均为 2026-10-19 实读核验（`.mooncakes/moonbitlang/async/` 为
> registry 0.22.x 解包，`src/` 为本仓工作区）。

## R1｜上游 `@http.Client` 公开面能力清单与缺口

逐条锚点：类型层 `.mooncakes/moonbitlang/async/src/http/pkg.generated.mbti`
（下称 http mbti）；实现层 `src/http/client.mbt`（下称 client.mbt）。

| # | 能力 | 锚点 | 池侧结论 |
| --- | --- | --- | --- |
| C-1 | 建连：`Client::Client(uri, headers?, proxy?, verify?, trust?)` | http mbti:64；client.mbt:117-125（`resolve_url` 补 path="/"，guard 单点） | **采用**（D13）。uri 不带路径可用 |
| C-2 | `Client::new` deprecated 别名 | client.mbt:115 `#alias(new, deprecated)` | **禁用**：`--deny-warn` 门判红（D13） |
| C-3 | `Client::close` 同步、幂等（仅首次生效） | http mbti:65；client.mbt:142-151（文档明示）；`IoHandle::close` io.mbt:71-81（先 detach、fd 有效才关、随后置 invalid） | **采用**：evict_all/超期/毒化/栈满关闭的唯一关闭原语；double-close 安全为兜底 |
| C-4 | `Client::skip_response_body()` | http mbti:80 | **采用**：残 body 调用方契约（P5/Q07）的执行原语 |
| C-5 | `Client::end_request()` | http mbti:67 | 归池前提「body 已消费完」的调用侧收口原语（P05 集成层使用；P04 只依赖契约不调用） |
| C-6 | 在途状态字段 | client.mbt 内部 priv（http mbti 无任何内省访问器） | **缺口**：池侧无法检测残 body ⇒ FR-011 能力边界的依据 |
| C-7 | fd/shutdown 探测 | http mbti 全文无 `fd`/`shutdown`（2026-10-19 grep 零命中） | **缺口（定性）**：fd 计数不可断言 ⇒ 无泄漏走双证据（裁决 Q04） |
| C-8 | `Client::drop(Self, Int) -> Int` | http mbti:66 | **不使用**：registry 解包内 grep 全 src 零命中，语义不可源证；优雅排水如未来需要，先登记 upstream 问题（须事先人工批准，宪法 I） |
| C-9 | `RequestMethod::Connect` | http mbti:118-124 | 是请求方法变体，**不是**建连 API（D13 同款证据） |
| C-10 | Host 头构造期固化 | client.mbt:58 `headers["Host"] = host.to_owned()` | Host/端口在构造期写进持久头 ⇒ **严禁跨 host:port 复用同一 Client** ⇒ Address 键必含端口（R4.3） |
| C-11 | 时钟 `@async.now() -> Int64`（ms） | async 根包 `src/pkg.generated.mbti:26`；`sleep` :40 | 超期判定的真实时钟源；测试注入替代（R2） |

## R2｜注入式时钟的落地形态（D15「超期判定为 now 的纯函数」的落地）

- **Decision**：池持私有可替换时钟字段
  `priv mut now_ms : () -> Int64`，缺省绑 `@async.now`；`IdleLease.idle_since`
  只在入栈瞬间记录一次 `now_ms()` 值，超期判定一律是
  `now_ms() - idle_since > keep_alive_ms` 的纯比较，判定路径无副作用、
  不推进时间。测试注入走**同包白盒**：`_wbtest.mbt` 与池同包，可调用私有
  构造入口 `priv ConnectionPool::with_clock(max_idle~, keep_alive~, now_fn~)`
  （或等价私有 mutator），把时钟换成受控序列/可控偏移；推进虚拟时间＝改
  偏移量或取序列下一个值，**零 sleep**。
- **为什么够用**：
  1. spec 的验收断言只要求「超期判定可被确定性地驱动到任一时刻」
     （spec Assumptions），白盒注入完全满足；US-3 场景 1 的两条超期连接
     在虚拟时间推进后由 `evict_expired()` 确定性剔除。
  2. 私有构造不进公开 `.mbti`：`ConnectionPool::new(max_idle?, keep_alive?)`
     保持 C4 裁决的两参数形态，测试需求不污染公开面（宪法 VI）。
  3. 惰性剔除（acquire/release 顺手剔除）与显式驱逐共用同一
     `now_ms()`，全部时间语义单点收口，无第二条时间路径。
- **Alternatives considered**：
  - `sleep` 串联真实时钟推进——**否决**：时间驱动抖动让验收踩在墙上钟
    竞速上（P03 已有 ±50ms 容差先例仍属不得已，见
    `scripted_server_test.mbt:67/:107`），且拖慢门禁；W07 工单明令禁止。
  - `now_fn` 作为 `new` 公开参数——否决：测试钩子进 `.mbti` 即公开承诺，
    违背「公开面最小」（宪法 VI）；且 C4 裁决 `new` 只有 max_idle/keep_alive
    两参。
  - 全局可变时钟单例——否决：跨测试用例污染、并行化后不可组合。

## R3｜`Mutex::try_acquire` 的 FIFO 陷阱与池侧锁策略

实测锚点：`.mooncakes/moonbitlang/async/src/mutex.mbt`——`:42`
`pub async fn Mutex::acquire`（异步）；`:51-52` 注释「`try_acquire` follow
the same FIFO rule of `acquire`: if there are `acquire` call waiting for the
mutex, `try_acquire` always return `false`」；`:53`
`pub fn Mutex::try_acquire(self) -> Bool`（同步、不 raise）；`:59-60`
「The mutex must have been acquired, otherwise the program will **abort**」。

- **陷阱（host 实测确认）**：有排队者时 `try_acquire` 恒 false——据此做
  「拿不到锁就跳过本轮驱逐」会形成**饥饿**；而 `release` 在未持有时调用
  直接 abort，配对纪律必须硬保证。
- **Decision**：按调用形态分流——
  1. **异步路径**（`ConnectionPool::acquire`）：临界区用
     `acquire()/release()`（异步原语，正常语义）。
  2. **同步路径**（`Lease::release`/`evict_expired`/`evict_all`）：无法
     await，用 `try_acquire()/release()`，**失败即 abort（fail fast），
     不静默跳过**——失败只可能意味着「有人跨 await 持锁」，即 FR-006
     不变量已被破坏，属实现级缺陷，应立即爆红而不是把验收变成概率事件
     （「跳过一轮」会让 SC-004 的确定性断言变成 flaky）。
- **为什么安全（不变量论证）**：池的全部临界区满足「无 IO、无 await、
  长度有界」（FR-006；实现纪律见 data-model 不变量表）。单线程协同式
  事件循环下，任何协程要么不持锁、要么在一次同步执行段内完成
  「上锁→改状态→解锁」，控制权让出点不存在持锁态 ⇒ 锁从不被跨
  await 持有 ⇒ ① 永远不存在排队等待者 ⇒ `try_acquire` 的 FIFO 恒
  false 分支不可达；② 同步路径的 `try_acquire` 实际恒成功（与
  `acquire` 等价，但保留了「万一笑破不变量就爆红」的防御价值）。
  异步 `acquire` 路径的锁也从不真正挂起——信号量在有许可时立即完成。
- **与 C3 裁决的关系**：owner 裁决保留 Mutex（Q4/Clarifications），
  本策略是「保留」的具体锁用法；「退化为普通字段」不在本包范围。
- **Alternatives considered**：同步路径静默跳过（否决：饥饿 + 验收
  flaky，正是 host 指出的陷阱）；同步路径改异步（否决：违反 D15
  「同步显式入口」裁决，defer/await 形态会把驱逐拖回调用方
  task group 的语义）。

## R4｜数据结构选型：LIFO 栈、Map 迭代序禁令、Address 端口隔离

### R4.1 LIFO 空闲栈

- **Decision**：每 Address 一个 `Array[IdleLease]` 作栈——归池 `push`
  到尾部，acquire `pop()` 从尾部弹出（尾=最热），栈满判定
  `length >= max_idle`。evict_expired 对每桶自尾向头扫描剔除超期项
  （splice 移除），evict_all 清空每桶并逐一 `close`。
- **Rationale**：`Array` 尾部 push/pop 摊还 O(1)，语义即 LIFO 本义
  （FR-004「最热连接优先」）；不需要任何有序结构。
- **Alternatives considered**：链表/双端队列——无收益（YAGNI）；
  「空闲队列 FIFO」——直接违反 FR-004，排除。

### R4.2 禁止依赖 `Map` 迭代序

- **Decision**：桶容器为 `Map[Address, Array[IdleLease]]`（`Address`
  提供 `equal`/`hash`，满足 `K : Hash + Eq`，无需 `Compare`）。**任何
  逻辑与断言不得依赖 Map 的迭代顺序**——驱逐/evict_all 对每桶独立收敛
  （结果只依赖桶内状态，不依赖桶间遍历序）；测试断言只对总量与按键
  查询的每桶计数说话。
- **Rationale**：内建 `Map` 的键约束只有 `Hash + Eq`（类型系统不提供
  序），上游实现虽为插入序链式哈希，但迭代序**不构成公开契约**——
  依赖它等于依赖实现细节。先例：夹具 `routes : Map[(String, String),
  ResponseScript]`（scripted_server.mbt:62）同样只做按键读写。
- **Alternatives considered**：按插入序遍历桶驱逐——否决（理由同上）。

### R4.3 Address 键含端口：严禁跨 host:port 复用 `Client`

- **Decision**：`Address = (scheme, host, port)` 三元组做池键，缺一不可；
  规范化（scheme/host 小写化、host 剥 IPv6 方括号）在 `Address::new`
  内部单点收口，规范化语义与 P01 `HttpUrl` 冻结面对齐（FR-014；
  P01 已交付：`src/core/pkg.generated.mbti:68-85`，且
  `HttpUrl::equal/hash` 的显式方法形态即 `Address::equal/hash` 的先例）。
- **Rationale**：client.mbt:58 在构造期把 `Host` 头写进持久头
  （`headers["Host"] = host.to_owned()`）——同一 `Client` 的 Host/端口
  在构造后不可改，跨 host:port 复用会把请求发到错误的源站（协议级
  错误，不是性能问题）。键隔离是 FR-014 的硬边界。
- **Alternatives considered**：忽略端口的「host 级」池化——否决（见
  上）；复用 P01 `HttpUrl` 类型直接做键——否决：Address 是「直连
  三元组」的窄语义（无 path/query/fragment），塞进 HttpUrl 会让键携带
  无关字段且 `parse` 会 raise（键构造必须 noraise）。

### R4.4 补记：`stale_evictions` 与 03 §3.4 的有意语义偏移（第二处登记）

- **偏移内容**：03 §3.4 毒化表原文的 `pool.stale_evictions += 1`
  （`03-connection-pool/README.md:102`，全篇唯一出现处）仅指
  「stale-retry 命中（02）」一行——原义是 P07 的 stale-retry 命中计数。
  本包裁决（spec Clarifications Q3，owner 2026-10-19）把该计数器定义为
  「仅计超期剔除」，并把「stale」扩展为「陈旧连接家族 ＝ 超期剔除 ＋
  P07 stale-retry 命中」。
- **理由**：① P04 内不存在 stale-retry（归 P07 承载，spec DoD-2 映射
  口径），若按原义则 P04 阶段该计数器恒为 0，US-3 场景 1 与 SC-004 的
  「剔除条数」断言失去观测面；② 扩展后 P07 落地时其命中行照 03 §3.4
  对**同一计数器** +1，同名同族（陈旧连接被清）、无二义、无第二计数器；
  ③ `evict_all`（可关未超期连接）与毒化/栈满（非「陈旧」语义）不计入，
  保住「stale」一词的限定力。
- **性质**：这是与上游文档的**有意语义偏移**（宪法 III「与 OkHttp 的
  语义差异必须显式记录」的同族纪律），非遗漏。analyze 对账
  「03 §3.4 ↔ 本包」时以本补记与 data-model 实体 2 注记（两处登记）
  为准，不构成矛盾。

## R5｜P03 夹具可观测性扩展（P9 裁决，implement 首片）

现状实测（`src/internal/fixtures/scripted_server.mbt`，2026-10-19 读）：

| # | 能力 | 现状锚点 | 状态 |
| --- | --- | --- | --- |
| F-1 | keep-alive 多请求连接处理 | `serve_connection` :212 起（循环 read_request→按路由应答） | 现有 |
| F-2 | 并发承载（串行 accept + spawn_bg 处理） | `serve_n` :269；accept 循环收口在夹具内（T008 裁决） | 现有 |
| F-3 | 在途/高水位观测 | `active_conns`/`peak_conns` :65-66，进出 +1/-1 :288-290/:302，访问器 :473 | 现有（口径不同，见下） |
| F-4 | echo 唯一 id / 帧形态 / 重定向等路由编排 | routes :62（Map），mount 覆盖式赋值 :170 | 现有 |
| F-5 | **累计 accept 连接数**（双证据外部证据） | 无任何累计 accept 计数（只有 active/peak 瞬时量） | **待建** |
| F-6 | **每连接请求数**（keep-alive 复用度的直接观测） | 无（连接级请求条数不落账） | **待建** |
| F-7 | **per-route 次序脚本**（同路由第 i 次命中取第 i 个响应） | 无——routes 覆盖式，同路由恒同一脚本 | **待建** |

- **Decision**：
  - F-5：`priv mut accepted_total : Int32`，`serve_once`/`serve_n` 的
    accept 成功点 +1；公开访问器 `accepted_total() -> Int`。
  - F-6：按 accept 序号记账 `priv conn_request_counts : Array[Int32]`
    （下标=连接序号），`serve_connection` 每完成一次请求 +1；访问器
    `conn_request_counts() -> Array[Int]`（拷贝语义，防内部别名逃逸）。
  - F-7：mount 增加次序形态——`RouteScript = Single(ResponseScript) |
    Sequence(Array[ResponseScript])`，第 i 次命中取 `min(i, len-1)`
    （末位驻留）；覆盖式 mount 语义保持不变，Sequence 是纯增量。
- **用途对账**：F-5 → US-2 场景 2 外部证据（FR-009：accepted_total ==
  池内新建数）；F-6 → 复用自证（长跑后存在 `count ≥ 2` 的连接 ⇒
  keep-alive 复用真实发生，且总量守恒）；F-7 → US-4 场景 2 的集成桩
  （第一响应可复用、第二响应带 `Connection: close`，验证管线侧毒化
  判定）与 US-3 的「超期后重新建连」观测。
- **`.mbti` 归因（T025 先例，003 tasks）**：`src/internal/fixtures` 是
  internal 包，`.mbti` 非对外承诺；但每个增面仍逐处归因——
  `accepted_total()`/`conn_request_counts()` → FR-009/US-2 场景 2；
  次序脚本类型与 mount 重载 → FR-010 集成桩/US-4 场景 2。归因写在
  tasks 对应条目，`moon info` 审视时按归因核对（违零即查）。
- **Alternatives considered**：在池侧自建一个「计数服务器」——否决：
  重复建设且绕开 P03 夹具单点收口（owner P9 裁决就是扩展夹具）；
  F-6 用 Map[conn_id, count]——否决：Array 序号已够，Map 键徒增依赖。

## R6｜`evict_expired`/`evict_all` 返回值与观测面（W06 遗留决策点）

- **Decision**：两入口均 `-> Unit`；观测走 `stale_evictions() -> Int`
  与 `per_host_total(addr) -> Int` 两个访问器 + 白盒直读内部状态
  （idle 长度、conn_id 守恒）。US-3 场景 1 的「剔除 2 条」断言＝
  `stale_evictions()` 前后差值；SC-004 同。
- **Rationale**：最小公开面（宪法 VI YAGNI）；spec 的验收面本就建立在
  FR-007 可读计数上；返回值是便利品，需要时可走 spec 变更扩面。
- **Alternatives considered**：`evict_expired() -> Int`（返回本次剔除
  数）——否决：观察者已存在（计数器），双份观测面徒增冻结成本。

## R7｜无泄漏双证据的执行设计（裁决 Q04）

- **外部证据**：长跑结束后 `fixtures.accepted_total() == 池内累计新建
  连接数`。池内累计新建＝`per_host_total` 按 key 求和（白盒直读
  `next_conn_id` 序号亦可，取其一定断言口径：**用白盒
  `next_conn_id - 1`**，避免求和遍历依赖 Map 迭代序——与 R4.2 自洽）。
  服务端侧看不到多余连接＝无泄漏。
- **内部证据**：`conn_id` 三态集合基数守恒——`借出 + 空闲 + 已关 =
  累计新建`。白盒断言：`borrowed.len + idle_count + closed.len ==
  next_conn_id - 1`，且三集合两两不交（同一 id 至多属于一个状态）。
- **双 target 同用**：native 与 wasm 跑同一套断言；长跑规模按 target
  分档——native ≥10k 请求；wasm/moonrun 按 t004-record.md 实测吞吐
  分档降额（具体数值 implement 期校准，上限以「单次显式运行 ≤ 数分钟」
  为界）。默认排除在常规六门外（裁决 C5），显式执行、证据登记。
- **禁写项**：fd 计数（C-7 缺口）；`extern "C"` 探测（宪法 I 红线）。

## R8｜测试组织、命名与「-p 假验证」警示

- **Decision**：测试全部落在被测包内（黑盒 `_test.mbt` + 白盒
  `_wbtest.mbt`），夹具扩展元测试落在 `src/internal/fixtures`：

| 文件 | 盒型 | 覆盖 |
| --- | --- | --- |
| `src/client/address_test.mbt` | 黑盒 | FR-014 键隔离/规范化、equal/hash |
| `src/client/pool_test.mbt` | 黑盒 | US-1/US-3/US-4 场景（P03 夹具 + `@http.Client` 原语独立驱动，不经 P05） |
| `src/client/pool_wbtest.mbt` | 白盒 | 时钟注入（R2）、conn_id 守恒（R7 内部证据）、终结幂等（FR-018）、临界区不变量、evict_all 不计数口径 |
| `src/client/pool_longrun_test.mbt` | 黑盒 | US-2 场景 2（双证据长跑；默认跳过，见下） |
| `src/internal/fixtures/scripted_server*.mbt`（增量） | 黑盒 | F-5/F-6/F-7 自证元测试（归因见 R5） |

- **命名约定**：`P04-<域><序> 描述`（域 ∈ US1/US2/US3/US4/E/FR/SC/
  LONGRUN），沿用 003 `P03-Bxxⓝ` 风格；`-f` 按测试名 glob 过滤。
- **长跑排除机制（裁决 C5 的机制落定，主案 + 降级案）**：
  - 主案：长跑测试声明 skip 属性（默认跳过），显式执行用
    `moon test -p <包> -f "P04-LONGRUN*" --include-skipped`。
    旗标核证情况：`-f`/`--include-skipped` 存在性已核证（003 research
    P-h）；skip 属性语法在 003 时点未核证——**implement 首任务先写
    1 秒级冒烟核证**，通过则定案。
  - 降级案（冒烟失败时）：长跑测试移入独立包（如 `src/client/stress/`），
    六门的 test 门改为「-p 枚举非 stress 包」，显式执行时单独 -p stress。
    代价：包枚举需随包增长维护（记录于 tasks 收尾）。
  - 两条路都保证：常规六门不含长跑（C5）；长跑证据随包级 DoD 登记。
- **「-p 假验证」警示（必须写进 quickstart 与任务口径）**：`moon test -p`
  **只认包名**（形如 `hahh9527/moonhttp/client`）；写成目录路径（如
  `-p src/client`）会**跑 0 个测试却返回 exit 0**——这是假绿。所有分包
  命令一律全包名，快速自检法：输出里 `Total tests:` 必须非 0。
- **双跑口径**：`moon test --target native --deny-warn` 与
  `--target wasm --deny-warn`；池与夹具全部公开 API，无 native-stub。
- **core 侧改动**：零（P04 不改 core 任何文件；`src/core/pkg.generated.mbti`
  期望零 diff）。
