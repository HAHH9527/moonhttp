# Data Model：P03 夹具库（src/internal/fixtures）

> 契约面见 contracts/fixtures-api.md；本文记录实体、字段、不变量与状态转移。
> 全部类型仅依赖 `@http`/`@socket`/`@async` 公开 API（宪法 I）。

## 常量（R4.5 校准决策）

| 常量 | 值 | 语义 |
| --- | --- | --- |
| `max_head_bytes` | 64KiB | 头部区长度上界（超限 Broken「头部超上限」） |
| `max_body_bytes` | 16MiB | 负载累计上界（超限即断，封顶累加不可回绕） |
| `max_size_line_bytes` | 1KiB | chunk 大小行**自身长度**上界（FR-006 判定支点） |
| `bind_retry` | 3 | 端口绑定冲突自动重试次数（FR-011） |
| `default_timeout_ms` | 5000 | 夹具每操作缺省超时（FR-004） |

## 实体 1：ResponseScript（第 1 类·路由编排声明，FR-012）

```text
pub struct ResponseScript {
  status : Int                      // 200/301/302/303/307/308/401/407…
  headers : Array[(String, String)] // Location / WWW-Authenticate / Connection: close 等
  framing : Framing                 // Fixed | Chunked（B-05）
  body : BodyPlan                   // Static | Echo | Drip（B-02/B-04）
  head_delay_ms : Int               // B-01：回响应头前的延迟
  close_after_response : Bool       // B-06：连接关闭头 + 实际关闭
}

pub enum Framing { Fixed | Chunked }
pub enum BodyPlan {
  Static(Bytes)                     // 定长静态体
  Echo                              // B-04：体 = "<id>:<请求体原样>"，id 为夹具单调分配
  Drip(block_bytes : Int, blocks : Int, interval_ms : Int)  // B-02：慢速滴流
}
```

校验规则：
- `Drip` 总量 = block_bytes × blocks ≤ 16MiB 对应客户端侧上限无关（服务端
  侧仅受脚本声明约束）；`interval_ms ≥ 0`。
- `Framing::Fixed` 时体长度必须先知（Static/Echo 可算；Drip 可算）——
  以 `extra_headers` 携带 `Content-Length`（server.mbt:190-197 公开契约）；
  `Framing::Chunked` 不带 CL，逐块 write+flush 保块边界。
- `Redirect`（B-03）＝ `status ∈ {301,302,303,307,308}` + headers 带
  `Location`（相对/绝对/畸形由声明值原样下发）；`Challenge`（B-08）＝
  `status ∈ {401,407}` + `WWW/Proxy-Authenticate` 头。

## 实体 2：ScriptedServer 句柄（生命周期状态机，FR-004/FR-011）

```text
pub struct ScriptedServer { priv server : @http.Server, priv routes, priv state }

状态机： Stopped ──start()──▶ Listening ──close()──▶ Closed
                    │  mount()*          ▲
                    └──serve_once()*─────┘（Serving 为 Listening 上的瞬态；
                       analyze F8：并发由测试侧 task group × serve_once 承载，不设 serve_n）

* mount(method, path, ResponseScript)：仅 Listening 态可声明（声明式编排面）
* serve_once(timeout_ms~)：accept 一条连接 → 循环 read_request → 路由匹配 →
  按 ResponseScript 编排应答 → 对端关闭/EOF/超时为止；整体受
  @async.with_timeout_opt(timeout_ms) 保护（公开面，async mbti:50）
* close()：幂等；关监听，不再 accept；在途连接由其操作超时上限收尾
  （优雅关闭语义，spec FR-004）
不变量：start 后 port() > 0（bind 127.0.0.1:0，冲突重试 ≤3，FR-011/FR-003）；
任何操作在最迟 timeout_ms 内返回（SC-006）
```

## 实体 3：PeerProgram / CutPoint（第 2 类·裸 TCP 程序，B-09～B-13）

```text
pub enum PeerProgram {
  AcceptClose                                   // B-09：accept 后立即 close
  CloseObservation                              // B-10：accept 后 close + 产出观测记录
  PartialResponse(cut : CutPoint, then_close : Bool)  // B-11：半截响应头注入
  SlowReceive(read_bytes : Int, interval_ms : Int)    // B-12：慢速接收
  Capture                                       // B-13：既有捕获（判定内核重写）
}

pub enum CutPoint {   // B-11 截断点参数化（spec FR-012/D3）
  Nothing                  // 0 字节即断（与 AcceptClose 同形，保留命名以对齐截断点清单）
  MidStatusLine(n : Int)   // 状态行片段 n 字节（US-2 场景 2：n=15）
  AfterStatusLine          // 状态行 + CRLF 后断
  MidHeaderLine(n : Int)   // 头行中间 n 字节后断
}

// run 返回值语义（analyze F3 收窄，与 contracts/fixtures-api.md §2 同口径）：
// 仅 Capture 程序的返回值承载捕获断言；其余程序返回值不承载断言语义。
```

## 实体 4：CapturedRequest（既有公开面，语义按 FR-005～FR-009 收紧）

```text
pub(all) struct CapturedRequest {
  head : Bytes      // 头部区（含最后一行 CRLF，不含空行 CRLF）
  body : Bytes      // 重组负载（定长截取或 chunk 拼接）
  raw : Bytes       // 已捕获全量字节：保序、保完整、不改动（FR-005）
  chunked : Bool
  complete : Bool
  note : String?    // 未收完如实说明；重复 CL/超上限/非十六进制等均可辨认
}
不变量：
- complete=true ⇔ 帧按判停口径收完；此时 body 与 raw 逐字节对应线上形态
- 判定结果与读取分片相位无关（FR-006）：feed 纯推进，同流任意切分同判定
- note 三型归一（FR-007）：超上限即时回报，绝不假 Complete、绝不滞留至超时
- 出现 ≥2 个 content-length 头 → complete=false 且 note 可辨认（FR-008）
```

## 实体 5：FrameScanner（内部状态机，不进公开面）

```text
priv enum ScanState {
  Head(bytes_seen)                       // CRLFCRLF 增量查找（3 字节跨块重叠）
  BodyFixed(remaining : Int)             // CL 定长计数消费
  ChunkSizeLine(line : Buffer)           // 大小行行缓冲（≤ max_size_line_bytes）
  ChunkData(remaining : Int)             // 数据块 + CRLF
  Trailer                                // 0 块后找 CRLFCRLF
  Done | Broken
}
feed(bytes) -> Signal  // Signal = NeedMore | Done | Broken(note)
转移为纯函数：判定只依赖 (state, 字节序列)，与切分相位无关（R4.1）
```

## 实体 6：RequestLineExpect（FR-009 断言辅助）

```text
pub struct RequestLineExpect { method : String, target : String }
pub fn CapturedRequest::assert_matches(self, expect, tag : String) -> Unit raise
// 断言：complete ∧ 请求行 == "\{method} \{target} HTTP/1.1\r\n" 前缀
```

## 实体 7：ObservationRecord（FR-015 观测清单行，B-10）

```text
struct ObservationRecord {
  target : String            // "native" | "wasm(moonrun)"
  pending_unread : Bool      // close 前是否有在途未读字节
  outcome : String           // "ReaderClosed" | "OSError"（仅此两类，E5）
}
// 以 println("[FR-015 观测] target=… pending=… outcome=…") 产出；
// 测试断言仅 outcome ∈ 二类集合；清单如实注明依 OS 与在途数据而变（D2）
```

## 实体关系

- `ScriptedServer` 1 ─▶ N `ResponseScript`（mount 声明）
- `ScriptedPeer`（RawPeer 扩展）1 ─▶ 1 `PeerProgram`（一次一条连接）
- `CapturedRequest` ◀─ 产出 ─ `PeerProgram::Capture`；◀─ 断言 ─ `RequestLineExpect`
- `ObservationRecord` ◀─ 产出 ─ `PeerProgram::CloseObservation` 元测试
