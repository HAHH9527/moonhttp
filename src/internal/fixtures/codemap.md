# src/internal/fixtures/

## Responsibility

内部测试夹具库（specs/003-m1-p03-test-fixtures）：为 moonhttp 客户端测试提供两类只监听
127.0.0.1 回环的可控服务端与线上帧判定工具，不对外发布为公共 API。
- `scripted_server.mbt`：第 1 类 @http 声明式编排服务端 `ScriptedServer`（B-01～B-06/B-08）。
- `raw_peer.mbt`：第 2 类裸 TCP 程序化对端 `ScriptedPeer`（B-09～B-13，自 P02 RawPeer 捕获底座演进）。
- `frames.mbt`：裸对端的**帧边界判定**面（判停，非 HTTP 解析），包内私有。

## Design

- `ScriptedServer`：`start()` 绑 127.0.0.1:0（bind 冲突重试 ≤ `bind_retry`=3），`port()` 取 OS 回填端口。
  声明面 `ResponseScript`（status/headers/`Framing` Fixed|Chunked/`BodyPlan` Static|Echo|Drip/head_delay_ms/close_after_response）
  经 `mount` / `mount_sequence`（按命中序取第 min(i,len-1) 个）/ `mount_interim`（先裸写 1xx）/ `mount_truncated`
  （下发完整头后不发体即断连）按 (method, path) 精确路由挂载。
- `ScriptedPeer`：一次 mount 一个 `PeerProgram`（`AcceptClose` / `CloseObservation` / `PartialResponse(CutPoint, Bool)` /
  `SlowReceive(read_bytes, interval_ms)` / `Capture`），`run(timeout_ms~)` accept 一条连接、按程序服务并返回
  `CapturedRequest`（head/body/raw/chunked/complete/note，raw 保序原样留存）；`CutPoint` 参数化半截响应头截断点。
- `frames.mbt`：私有 `FrameScanner` 增量状态机（Head/BodyFixed/ChunkSizeLine/ChunkData/…/Trailer），`feed` 每字节
  恰好处理一次、不重扫历史；夹具保护上限 `max_head_bytes`(64KiB) / `max_body_bytes`(16MiB) /
  `max_size_line_bytes`(1KiB) 独立封顶累加，畸形输入不 panic、如实回报 Failed(note)。
- 全部只用 moonbitlang/async 公开 API（@http/@socket/@async）；超时统一经 `@async.with_timeout_opt` 兜底，不悬挂；
  accept 串行（上游 `TcpServer::accept` 并发不安全），连接处理经任务组 `spawn_bg` 并发。

## Flow

测试驱动路径：`start()` → `port()` 得实际端口 → `mount…`/`mount(program)` 声明编排 → 客户端对回环端口发请求 →
服务端 `serve_once`/`serve_n`（多连接、可观测 `peak_concurrent`/`accepted_total`/`conn_request_counts`）或对端
`run()` 执行程序 → 断言：`CapturedRequest::assert_matches`（配 `expect_request_line` 构造 `RequestLineExpect`）/
观测位读取 → `close()` 幂等收尾（停止后新操作如实返回，不再 accept）。

## Integration

- 依赖：`moonbitlang/async`、`async/http`、`async/socket`；`async/io` 仅测试可见（错误分类判别），不入运行时依赖。
- 消费方：`src/core` 与 `src/client` 的测试（黑盒/常规 import 均仅测试引用，运行时依赖不经过本包）。
- 上游取证锚点：@http 发送侧 chunked/定长帧形态、`TcpServer` accept 约束等以 moonbitlang/async 公开面为准，
  不 fork、不 vendor 上游源码。
