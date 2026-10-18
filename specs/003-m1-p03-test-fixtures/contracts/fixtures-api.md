# 契约：internal/fixtures 包公开面（模块内可见）

> 包路径：`hahh9527/moonhttp/internal/fixtures`（C1 裁决，research.md R1.3）。
> 可见性：仅本模块可导入（toolchain internal 规则强制，探针 P-a/P-b/P-c）；
> `.mbti` 不构成对外承诺。消费方：本包元测试、`src/core` 黑盒测试
> （`for "test"` 导入）、P04–P10 后续测试。
> 全签名仅依赖 `@http`/`@socket`/`@async` 公开 API（宪法 I）。

## 1. 第 1 类：脚本化 HTTP 服务端

```moonbit
pub struct ScriptedServer

/// 绑定 127.0.0.1:0（冲突重试 ≤3）并监听；FR-003/FR-011
pub async fn ScriptedServer::start() -> ScriptedServer raise

/// 实际监听端口（bind :0 回填，恒 > 0）
pub fn ScriptedServer::port(self : ScriptedServer) -> Int

/// 声明式路由（FR-012）：一次调用声明一个路由的完整响应编排。
/// 仅 start 之后、close 之前可调用；method+path 精确匹配。
pub fn ScriptedServer::mount(
  self : ScriptedServer, method : String, path : String, script : ResponseScript
) -> Unit

/// accept 一条连接并按脚本服务至对端关闭/EOF；
/// 整体受 with_timeout_opt(timeout_ms) 保护（FR-004），超时关连接不悬挂。
pub async fn ScriptedServer::serve_once(
  self : ScriptedServer, timeout_ms~ : Int = 5000
) -> Unit raise

/// 幂等停止：关监听不再 accept；在途连接由其操作超时上限收尾（FR-004）
pub fn ScriptedServer::close(self : ScriptedServer) -> Unit
```

行为子句（每条对应行为清单编号与自证元测试义务 FR-002）：

- B-01 `head_delay_ms`：`send_response` 前延迟；元测试用 `@async.now()` 断言
  观测头时延符合编排。
- B-02 `BodyPlan::Drip(block_bytes, blocks, interval_ms)`：逐块 write+flush，
  块间 sleep；元测试断言块到达间隔与编排一致。
- B-03 重定向：`status ∈ {301,302,303,307,308}` 且 headers 携带 `Location`
  （相对/绝对/畸形按声明原样下发）；链路由多路由 Location 互指表达。
- B-04 `BodyPlan::Echo`：响应体 = `"<id>:<请求体原样>"`，id 单调唯一
  （FR-013）；并发 N 请求 id↔请求体一一对应。
- B-05 `Framing::Fixed` ⇒ `extra_headers` 带 `Content-Length: n` 且写满 n
  字节；`Framing::Chunked` ⇒ 不带 CL，块边界经 flush 保真。元测试以线上
  字节断言帧形态（捕获对端或原始读）。
- B-06 `close_after_response=true` ⇒ 响应携带 `Connection: close` 且应答后
  实际关闭连接。
- B-08 `status ∈ {401,407}` + 对应 Authenticate 头（M2 备用，M1 仅可编排+自证）。
- B-07 gzip：**M1 缺口·推迟**（裁决 D4），不建模。

## 2. 第 2 类：裸 TCP 脚本对端

```moonbit
pub enum PeerProgram {
  AcceptClose
  CloseObservation
  PartialResponse(cut : CutPoint, then_close : Bool)
  SlowReceive(read_bytes : Int, interval_ms : Int)
  Capture
}

pub enum CutPoint { Nothing; MidStatusLine(Int); AfterStatusLine; MidHeaderLine(Int) }

/// 既有 RawPeer 的程序化扩展：一次 start 服务一条连接一次断言（口径不变）
pub struct ScriptedPeer
pub async fn ScriptedPeer::start() -> ScriptedPeer raise
pub fn ScriptedPeer::port(self : ScriptedPeer) -> Int
pub fn ScriptedPeer::mount(self : ScriptedPeer, program : PeerProgram) -> Unit
pub async fn ScriptedPeer::run(self, timeout_ms~ : Int = 5000) -> CapturedRequest raise
// 返回值语义（analyze F3 收窄）：仅 Capture 程序的返回值承载捕获断言；
// 其余程序（AcceptClose/CloseObservation/PartialResponse/SlowReceive）的
// 返回值不承载断言语义——客户端侧结局由元测试分类并打点
// （见 contracts/wire-observations.md）。
pub fn ScriptedPeer::close(self : ScriptedPeer) -> Unit
```

行为子句：

- B-09 `AcceptClose`：accept 后立即 close（客户端预期 EOF/ReaderClosed 类
  错误，US-2 场景 1）。
- B-10 `CloseObservation`：close 前按前置条件写 0/N 字节；客户端读结局仅
  断言 ∈ {@io.ReaderClosed, @os_error.OSError}（E5）；观测记录按
  contracts/wire-observations.md 产出（FR-015）。**不承诺 RST**（D2/E3）。
- B-11 `PartialResponse`：按 CutPoint 发送 canned 响应字节前缀后（可选）断；
  验收判据＝客户端错误落在钉死集合 {BadRequest, ReaderClosed} 内
  （spec D3/E4；不以「状态行已解析」为判据）。
- B-12 `SlowReceive`：按声明节奏读，不读满（P08 写侧超时场景）。
- B-13 `Capture`：既有捕获语义（五字段 + note 不变），判定内核按
  research.md R4.1 重写。

## 3. 捕获与断言辅助

```moonbit
pub(all) struct CapturedRequest {
  head : Bytes
  body : Bytes
  raw : Bytes
  chunked : Bool
  complete : Bool
  note : String?
}
pub fn CapturedRequest::head_text(self) -> String   // Latin-1 渲染，既有
pub fn CapturedRequest::raw_text(self) -> String    // 既有

pub struct RequestLineExpect { method : String, target : String }
/// FR-009：请求形态是断言入参，辅助不预设方法/路径
pub fn CapturedRequest::assert_matches(
  self : CapturedRequest, expect : RequestLineExpect, tag : String
) -> Unit raise
```

判定子句（继承缺陷回归，判停口径文件头注释同步更新）：

- FR-006 chunked 判定与分片相位无关；大小行以 `max_size_line_bytes`(1KiB)
  自身长度为界；>64KiB 负载完整收完。
- FR-007 数值封顶累加：超 `max_body_bytes`(16MiB) 即时 Broken「超出夹具
  上限」；不回绕、不滞留。
- FR-008 ≥2 个 content-length 头 ⇒ Broken「重复 Content-Length」
  （与 TE 在场无关，TE 分派前判定）。
- FR-005 raw 保序保完整；畸形/未收完路径已匹配字节全数留存；不 panic。
- FR-010 捕获耗时不随体积平方增长（增量推进，每字节处理一次；SC-003 判据）。
