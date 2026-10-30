# Research: 连接失败重试 stale-retry（M1-P07）

> 2026-10-30。证据基线：spec.md（含 qod-1 复核修正）、三路 explorer
> 取证（proj-init-docs / 上游 .mooncakes / 本地 specs+src）、qodercn
> 独立复核。本文只记决策与锚点，不重复 spec 论证。

## R1 recover 落位与形态：轮内尝试子循环 + 阶段标记插桩

**Decision**: recover 实现为 `exchange_loop` 每轮内部的尝试子循环
（至多 2 次 attempt），外层 follow-up 循环结构、`follow_ups` 计数、
决策表推进、prior 链零接触。阶段信息经 `Call` 新增 priv 可变字段
传递，不拆 `exchange_with_lease`、不改其签名。

**Rationale**:
- qod-1 阻断项②：轮内 catch 与「轮级 errdefer 唯一毒化归属」不能
  同时字面成立——errdefer 仅在错误逸出块时触发（006 实测锚点
  follow_up.mbt:249-252 注记 + follow_up_wbtest.mbt P06-WB④c）。
  折中为 spec FR-007 底线约束 + 机制分工：
  - **重试路径**：捕获分支内显式 `poison_release()`（毒化+close+lease
    置 None）→ 计数（仅 stale 族）→ continue 下一 attempt；
  - **逸出路径**（不可重试 re-raise）：轮级 errdefer 原样触发，归属
    不变；同批修订 006 data-model D-2 措辞（唯一性限于逸出路径）。
- 「重入外层循环」被否决：会污染 follow_ups 计数与决策表推进，
  与 006 实体结构冲突（qod-1 同点）。
- 阶段标记选 priv 字段而非函数拆分：三行相似代码优于过早抽象；
  `exchange_with_lease` 的四个调用点（request/write_once/filler/
  end_request，exchange.mbt:122/127/129/135）各前置一行赋值即可，
  逸出路径行为零变化。

**Anchors**: follow_up.mbt:241-291（轮结构）、exchange.mbt:114-164
（阶段平铺）、http_client.mbt:174-190（execute catch 只映射取消）。

**形状（伪码，implement 以红绿定稿）**:

```text
每轮 follow-up:
  guard 取消
  addr = address_of_request(request)
  attempts = 0
  resp = loop {                       # 轮内尝试子循环
    attempts += 1                     # 1=原始尝试，2=重试
    # —— 建连段捕获（此时无租约，池状态零变化契约）——
    try ensure_lease(addr)
    catch err:
      d = decide(Connect, family(err), …, attempts, …)
      d=Retry → continue；否则 raise（无租约，无毒化义务）
    # —— exchange 段捕获（轮级 errdefer 在首轮 attempt 前登记）——
    try exchange_with_lease(request, lease)
    catch err:
      f = family(err)                 # 按 last_stage 细分阶段已在 family 输入
      d = decide(…, attempts, …)
      d=Retry → poison_release();  f=Stale → note_stale_hit();  continue
      否则 raise err                  # 逸出 → 轮级 errdefer 毒化（归属不变）
    break resp                        # 成功出子循环
  }
  …（决策表/排干/换代照旧）
```

## R2 上游错误面与判别形态（全锚点）

| 事实 | 锚点 | 对本包的含义 |
| --- | --- | --- |
| `ReaderClosed` 无载荷、`pub(all)` 可跨包构造 | io/pkg.generated.mbti:16、reader.mbt:31 | 判定器单元级可构造 |
| `OSError(Int, context~)` `pub(all)` | os_error/error.mbt:73-75 | 同上；`is_ECONNREFUSED` 判别在场（:151-158） |
| `BadRequest`/`HttpVersionNotSupported`＝`HttpProtocolError` 族变体，`pub` 非 `pub(all)` → 跨包**不可构造** | http/pkg.generated.mbti:31-35 | 族检测分支以集成场景覆盖（B-11）；`err is @http.BadRequest` 判别形态有仓内先例（scripted_peer_test.mbt:122） |
| `IncorrectBodyLength` 独立 `pub suberror`（非 pub(all)） | http/pkg.generated.mbti:37 | 同上；注入＝Content-Length 头与实发不符 |
| `TlsError(String)`/`ConnectionClosed` `pub` 非 `pub(all)` → 不可构造 | tls/pkg.generated.mbti:15-21 | 判定框架级（spec C1）；TLS 错误缓存态（transport.mbt:65-86）佐证失败后必须弃连接 |
| `ResolveHostnameError` `pub` 非 `pub(all)` → 不可构造 | socket/pkg.generated.mbti:16 | 同 TLS 处理 |
| parser 抛出点：零字节 EOF→ReaderClosed（:401-403）；畸形状态行→BadRequest（:404/:410-413）；版本→HttpVersionNotSupported（:405-408）；头段 EOF→ReaderClosed（:258）、畸形头→BadRequest（:265/:268） | http/parser.mbt | FR-002 分流的错误源；F17 实测三 ReaderClosed 形态 |
| `write` 进度丢弃、`write_once` 为缓冲拷贝计数（1024B） | io/writer.mbt:28-42、http/send.mbt:85/:112-122 | 字节级「已写出」不可观测（spec C2） |
| 写失败可推迟到 flush/end_request（end_body→flush） | send.mbt:93-100、client.mbt:236 | 读头阶段错误可能含体数据残余的 flush 失败——阶段语义按 L1 调用点定义即可 |
| Windows EOF 折算（ERROR_HANDLE_EOF/BROKEN_PIPE→读 0） | io_windows.mbt:136-143、io_windows.c:346-348 | OSError 与 ReaderClosed 同入 stale 族（R1 裁决承接） |
| `@async.retry(Immediate|FixedDelay|ExponentialDelay, max_retry?, fatal_error?)` 存在 | async/pkg.generated.mbti:34、async.mbt:218-266 | 本包不引入（无退避需求）；未来 max_attempts>2 的承接点 |
| Happy Eyeballs 竞速：全败重抛第一条错误、250ms 错峰 | socket/happy_eyeball.mbt:30-106 | 建连失败＝竞速全败后透传；「整体重来一次」语义成立 |
| 上游 Client 失败后状态不可复用（TLS 缓存错误态；close 幂等） | tls/transport.mbt:65-86、client.mbt:141-151 | 重试必须弃旧连接（FR-005） |

## R3 `Stream` 体封锁口径：filler 调用即置位（保守上界）

**Decision**: `stream_body_written` 在 **filler 被调用前置位**（每
attempt 复位）。

**Rationale**: 精确的「至少一次底层写调用成功」需要包装 filler 的
连接写面——filler 形参为上游 `Client`（exchange.mbt:129
`filler(lease.conn)`），包装须改 `BodySource::Stream` 回调签名（core
公开面 diff，违 FR-011 冻结意图）。spec 已授权保守封锁方向
（「宁可漏重试不可误重试」，机制归 plan 裁定）；「调用即置位」是
FR-003 封锁条件的保守上界（多封锁「已调用但零成功写」的可重试子
情形——该子情形缺失重试的代价 ≪ 误重放一次性体的风险）。

**否决替代**: 拆 `exchange_with_lease` 成 send/read 两函数以在函数
边界区分阶段——签名不变但结构变更大于字段插桩，且读头段仍需独立
捕获点，两层改动无收益。

## R4 判定器两层形状：族检测（按 target 分文件）+ 决策函数（纯、全可测）

**Decision**:

```text
priv enum SendStage    { Connect; Send; ReadHead }          # 全 target 可见
priv enum ErrFamily    { Stale; Protocol; ConnectFailure; Other }
priv enum RetryDecision{ Retry; Fail }

priv fn error_family(err : Error) -> ErrFamily                   # recover.mbt [native,wasm]
                                                                 # recover.js.mbt [js]：恒 Other
priv fn decide(stage, family, body : @core.BodySource?, stream_body_entered : Bool,
               attempts : Int, enabled : Bool, cancelled : Bool) -> RetryDecision
```

- `decide` 纯函数：输入全部可构造 → 白盒矩阵全分支用例（FR/US 判
  定分支的可测性主体，宪法 IV）。
- `error_family`：native/wasm 文件命名 `@io.ReaderClosed`/
  `@os_error.OSError`/`@tls.TlsError`/`@tls.ConnectionClosed`/
  `@socket.ResolveHostnameError`/`@http.BadRequest` 等类型——其中可
  构造族（ReaderClosed/OSError）单元级直测；不可构造族（协议族/
  TLS 族/ResolveHostnameError，`pub` 非 `pub(all)` 跨包不可构造）以
  集成场景（B-11 MidHeaderLine→Protocol；Content-Length 谎报→
  IncorrectBodyLength）覆盖，**诚实边界记录**：TLS 族/
  ResolveHostnameError 分支在 M1 无任何可注入通道，判定框架级，
  M2 TLS 场景扩展时接管（spec C1/R1 已预留口径）。
- js 降级：`error_family` 恒 `Other` ⇒ `decide` 恒 `Fail`（透传），
  语义＝重试不激活（spec Target 矩阵）。

**Rationale**: 决策/检测分层把「不可构造输入」隔离在检测层，决策
层全分支可测满足宪法 IV 的分支覆盖义务；target 分文件机制与上游
client.mbt/client.js.mbt 同款（http/moon.pkg targets 表实证）。

## R5 stale 计数入口：同包私有方法

**Decision**: `ConnectionPool` 增 priv 方法 `note_stale_hit(self)`：
`@async.Mutex` 锁内 `inner.stale_evictions += 1`（与 acquire/release/
evict_bucket_locked 同锁形态，INV-4 临界区约束满足——无 IO 无
await）。调用点＝重试分支且 `family == Stale` 时、`poison_release()`
之后。

**Rationale**: 字段 priv 且唯一递增点在 evict_bucket_locked
（client.mbt:348-364, :360）；004 FR-007 语义扩展行已预留「P07 命中
行对同一计数器 +1」；公开 setter 违 FR-011（stale 计数入口保持私
有）。同包直读先例在场（follow_up.mbt:213/:271 读 `lease.addr`）。

## R6 js 编译面：target 分文件 + 空包 import

**Decision**: `src/client/moon.pkg` 增 `moonbitlang/async/os_error`/
`tls`/`socket` 三个 import（三包在 js 上编译为空包——全部实现文件
锁 [native,wasm]，os_error/moon.pkg 与 tls/moon.pkg targets 表实
证；上游 @http 无条件 import @tls 而 js 可编译为同构先例）。判定器
族检测按 target 分文件：`recover.mbt`〔native,wasm〕/
`recover.js.mbt`〔js〕。

**Rationale**: 上游 `targets` 机制即为此设计（http 包 client.mbt/
client.js.mbt 对）；`decide`/枚举定义放全 target 可见文件，
js 侧无任何对锁定类型的引用。js check 若报新增 import
unused_package（js 上三包无引用点）——js 非门禁目标，如实记录不抑
制（plan Complexity Tracking）。

## R7 夹具扩展：静默关闭组合变体（US-1 依赖）

**Decision**: `raw_peer.mbt` 新增 PeerProgram 变体（命名 implement
定，建议 `SilentCloseThenServe`）：同一监听端口顺序处理两条连接——
第一连接：读尽请求帧（drain 内置，D12 教训：先读后 close ⇒ FIN 确
定性）→ 回 200 + Content-Length（**不带** `Connection: close`，与
B-06 close_after_response 的关键差异）→ 静默 close；第二连接：正
常 serve（canned 200 → close 或保持）。入 fixtures 公开面
（.mbti）。

**Rationale**: 现有变体无一满足「应答后静默关闭空闲连接 + 二次
accept」——B-06 必带 close 头（客户端主动毒化，不构成 stale）、
AcceptClose 无第一跳正常应答、Capture 单连接一次性（exp-3 盘点）。
时序确定性论证：响应体字节先于 FIN 进入接收缓冲，客户端读满
Content-Length 即 Consumed 回池，不受 close 时序影响；二次
execute 取出死连接 → end_request 读到 0 字节 EOF → ReaderClosed
（FR-015 观测清单形态）。

## R8 US-2 拒绝形态观测清单（FR-015 同款手法）

**Decision**: 新增双 target 元测试：对无监听端口发起 connect，记录
错误实际形态（native/wasm 各一份），钉定后加入 US-2-1 断言。先行
断言收窄为「原始错误透传 + 恰 2 次尝试 + 池状态零变化」。

**Rationale**: FR-015 只实测过 close 的 FIN/RST 形态，refused-connect
未实测（qod-1 5c）；native 侧预期 `OSError(ECONNREFUSED)`（network_unix.mbt:191-201 + is_ECONNREFUSED 在场），wasm/moonrun 侧待实测。

## R9 006 D-2 措辞修订与 codemap 收尾

**Decision**: implement 同批完成两处文档修订：
1. `specs/006-m1-p06-redirects/data-model.md` D-2 行加注：「轮级
   errdefer 是轮内失败的唯一毒化归属点」→ 唯一性限于**错误逸出路
   径**；重试路径毒化由捕获分支显式完成（P07 修正，2026-10-30，
   spec FR-007 底线约束承接）。
2. `src/client/codemap.md` 订正既有漂移（「两错误变体」→ 三变体实
   况）+ 补 recover 文件职责。

## R10 FR/US ↔ 测试映射表（宪法 IV 对账面）

| 判定分支 / 场景 | 级别 | 载体 |
| --- | --- | --- |
| 开关关闭 → 恒不重试 | 集成 | call_test：开关 false + stale 注入 → 原错误透传、stale_evictions 0 |
| Stale 族（ReaderClosed/OSError）→ Retry | 白盒 | recover_wbtest：可构造值矩阵（stage×body×attempts×cancel×switch） |
| Stale → 计数 +1（与结果无关） | 集成 | call_test：K 次独立 execute（US-4-1）+ 耗尽路径计数已发生 |
| Protocol 族 → Fail + 毒化 + 零计数 | 集成 | call_test：B-11 MidHeaderLine（US-3-1）；计数对照断言 |
| ReaderClosed 集成形态 → 重试成功 | 集成 | call_test：B-11 Nothing/15B/17B（US-3-2）+ US-1 闭环 |
| Stream 已进入发送 → Fail | 集成 | call_test：AcceptClose + Stream 体（US-3-3）——错误 ∈ {ReaderClosed, OSError} 且对端单连接 |
| Stream 未进入 → Retry | 白盒 | recover_wbtest：decide(stream_body_entered=false) |
| Bytes 恒可重放（部分写出后） | 集成 | call_test：B-11 + Bytes 体重放，捕获对端字节一致（SC-004） |
| 尝试预算 ≤2/代次、耗尽透传 | 白盒+集成 | recover_wbtest（attempts 边界）+ call_test（关闭端口 2 次尝试，US-2-1/R8） |
| 建连失败 → Retry、零毒化零状态变化 | 白盒 | recover_wbtest（ConnectFailure 族决策）+ 池计数断言 |
| 取消优先（含重试轮间） | 集成 | call_test：execute 中 cancel → 裸 CallCancelled（US-3-4） |
| 同代次重放零重折叠、字节一致 | 集成+白盒 | call_test（fold_count 白盒断言或捕获对端）+ follow_up_wbtest |
| 重试+301 叠加：不占跳数、无 prior 条目 | 集成 | call_test：stale 恢复后 301 → 终态、prior 链深 1、follow_ups 语义不变（SC-006） |
| TLS 族/ResolveHostnameError → Retry（框架级） | 诚实边界 | 无注入通道（R4）；decide 层以 ErrFamily::Stale/ConnectFailure 直测兜底 |
| IncorrectBodyLength → Fail + 毒化 | 集成 | call_test：Content-Length 谎报 → 原错误透传 |
| 拒绝形态双 target 观测清单 | 元测试 | fixtures/fr015 同款（R8） |

## R11 快乐路径零回归论证

判定器只在 catch 分支执行；try 本身在 MoonBit 编译为零成本直落
（无异常表展开的运行时开销模型，错误路径构造才分配）。`last_stage`
/`stream_body_written` 为每 attempt O(1) 赋值。P10 基准回归由其场
景矩阵承接（含 006 D17 follow-up 行）；本包验收不断言延迟数字。
