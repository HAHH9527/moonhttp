# Contract: timeout-api（client/core 公开面增量契约 + priv 接缝 + 夹具增量）

**Branch**: `008-m1-p08-timeouts` | **Date**: 2026-10-30
**对账基准**：spec FR-012 冻结面；实现完成后 `.mbti` diff 以本文为对
账面，计划外公开项为零。007 contracts/retry-api.md 同款体裁。

## §1 公开面增量（恰四项，按包）

### src/client（三项）

1. **HttpTimeout**：`pub suberror HttpTimeout derive(@debug.Debug)`，
   变体恰四：`Connect` / `Write` / `Read` / `Call`（判别面 `err is`；
   Debug 派生沿 CallCancelled 先例，P01 HeadersError→extend to_repr
   形态按 007 现行三变体同款）。
2. **Timeouts**：`pub struct Timeouts` 四字段带缺省
   （connect_ms/write_ms/read_ms = 10_000，call_ms = 0），
   `derive(Debug)`；无方法（纯值对象）。
3. **HttpClientBuilder 派生面**：
   - `pub fn HttpClient::new_builder(pool : ConnectionPool) -> HttpClientBuilder`
     （pool 根构造，全缺省）
   - `pub fn HttpClient::builder(self : HttpClient) -> HttpClientBuilder`
     （自既有 client 派生：pool 引用共享、标量缺省取自被派生方当前
     值——OkHttp `client.newBuilder()` 同形；FR-009 双入口）
   - `pub struct HttpClientBuilder`（字段全 priv）+ 链式 setter：
     `timeouts(Timeouts)` / `follow_redirects(Bool)` /
     `follow_ssl_redirects(Bool)` / `retry_on_connection_failure(Bool)`
   - `pub fn HttpClientBuilder::build(self) -> HttpClient`（负值校验
     单点，abort——C5/004 先例）
   - 双构造入口 + setter + build 计 1 个语义面项（FR-012 口径③：
     构造器/setter/校验为同一派生面的组成部分）。

`HttpClient::new` 签名不变（行为增量＝字面量补缺省配置）；HttpClient
新增 priv 字段不进公开面。

### src/core（一项）

4. **Request::new_builder**：
   `pub fn Request::new_builder(self : Request) -> RequestBuilder`——
   五要素保三换：headers 逐项与 tag 保留、url/method/body 可经既有
   RequestBuilder 链式覆盖（复用同一构建器，新增派生构造入口，R6）；
   无超时位（C2）。

## §2 priv 接缝（不进 .mbti，白盒断言面）

| 接缝 | 位置 | 契约 |
| --- | --- | --- |
| `Call.call_timeout_fired : Bool` | http_client.mbt | 看门者标记；置位先于 task.cancel（R1 时序）；一次性无复位（I-1） |
| 看门者 spawn | http_client.mbt execute | call_ms>0 才派生；`sleep(call_ms) → 置位 → task.cancel()` 三步序（FR-002 有界例外①） |
| 取消收尾变体选择 | http_client.mbt execute Cancelled 分支 | 标记真 ⇒ `HttpTimeout::Call`；假 ⇒ 裸 `CallCancelled`（现状逐位不变） |
| 连接伞包裹 | follow_up.mbt ensure_lease | `with_timeout(connect_ms, pool.acquire(addr), error=HttpTimeout::Connect)`；每 attempt 新伞（FR-002 有界例外②） |
| 写窗三接点 | exchange.mbt | header `request` 包窗 / Bytes `write_once` 包窗 / Stream 经 Writer 门面（filler 实参替换） |
| Writer 门面 | exchange.mbt（priv struct） | 实现 `@io.Writer` 三方法，各包 `with_timeout(write_ms, ..., error=HttpTimeout::Write)` 后委托内层 conn |
| 读窗两接点 | exchange.mbt / body_bridge.mbt | `end_request` 包窗（收头单窗，C4）；read_checked 内层读包窗（体读） |
| error_family 三行 | recover_family.mbt | `err is HttpTimeout`：Connect 变体∧stage=Connect ⇒ ConnectFailure；余 ⇒ Other（decide 零改动） |
| follow_up_request 两参 | follow_up.mbt | `follow_redirects~`/`follow_ssl_redirects~`，门序对拍 5.5.0（R7）；调用点从 self.client 直读透传 |

## §3 夹具增量（src/internal/fixtures，spec Assumptions 登记）

1. **DripHang**（ScriptedServer Framing 新变体）：`DripHang(block_bytes,
   blocks, interval_ms)`——按 B-02 Drip 节奏滴 blocks 块后长睡保持连
   接（不 close、不 EOF）。US-2-2 载体。
2. **SilentReader**（ScriptedPeer 新指令变体）：按极慢节奏读请求体
   且不关闭连接（B-12 SlowReceive 收尾 close，不满足写停滞保持）。
   US-1-3 载体；体量口径 ≈1MB Stream 分块（填满对端接收窗 + 发送缓
   冲，判据 write_ms ≥ 60ms——qod-1 B4 实测量级）。

其余场景零夹具新增：US-1-2/1-4/US-4/US-5/US-6 由 B-01/Drip/301 编排/
ServeSequence × 参数组合承载；1xx+慢头（C4）由 F-8 interim 能力 ×
B-01 组合。

## §4 js 形态（FR-011，非门禁）

新增公开类型与接线代码全 target 中性（无 #cfg、无 .js.mbt 分文件，
research R12）；js 语义＝调用方侧变体可用、底层 fetch 不保证取消
（上游 AbortController 内建自用，B6 取证）；`moon check --target js`
与基线 13 既有错误对账零新增。降级清单＝本契约 §4 + spec 映射表 js
行 + README 用户文档段（implement 交付）。

## §5 质量门（合入判据，宪法）

1. `moon info && moon fmt` 干净；`.mbti` diff 恰 §1 四项。
2. `moon test --target native` 与 `--target wasm` 双绿（含既有全量回
   归——research R11）。
3. `moon check --target js` 零新增错误（基线 13）。
4. 全部测试仅触 P03 本地夹具（SC-009 断网全绿）。
