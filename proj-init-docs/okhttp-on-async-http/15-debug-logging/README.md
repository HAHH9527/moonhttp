# 15 调试日志（Debug Logging）

> 结论：**非侵入可实现**。OkHttp 的内部调试 API（HTTP/2 帧日志 `<<`/`>>`、TaskRunner 日志）在我们体系里对应 L1 各层 + （未来的）H2 帧层的结构化日志门面。

## 1. OkHttp 行为规格

- 基于 `java.util.logging` 的内部调试 API：HTTP/2 帧收发日志（方向标记 `>>`/`<<` + 帧摘要）、TaskRunner 任务调度日志（任务开始/结束/延迟）。
- 运行时开关（如 Android `adb setprop log.tag.Http2 DEBUG`），不重编译。
- 定位是**内部诊断**，非应用日志门面。

## 2. async/http 现状（证据）

- 无任何日志设施（`@http` 零日志调用；error path 全部类型化 raise）。
- MoonBit 无 JVM 式全局 logging manager——运行时开关需自建。

## 3. 实现方案

### 3.1 日志门面（L1 内建，~100 行）

```moonbit
pub struct Logger {
  trace : (LogEvent) -> Unit     // 默认 no-op；事件结构体（category, direction?, payload 摘要）
  debug : (LogEvent) -> Unit
}
pub struct LogEvent { category : LogCategory, detail : String, ts : Int64 }
priv enum LogCategory { Http1Wire | Http2Frames | Pool | Dispatcher | Cache | Dns | Tls }
```

- 挂点：池取放/驱逐（03）、Dispatcher 出队（10）、缓存决策（05，cache-simulator 级别）、**H2 帧层（13）**——帧日志对齐 okhttp `Http2` logger 格式：`>> 0x00000003 HEADERS (flags=END_HEADERS) len=218`。
- H1 线缆日志（okHttp 没有对应物，是我们增值）：应用拦截器形态的 `WireLoggingInterceptor` 打请求/响应头摘要。
- **脱敏**：`Authorization`/`Cookie`/`Set-Cookie`/`Proxy-Authorization` 值替换 `<redacted>`（okhttp 日志拦截器生态的标配行为，库内建防泄漏）。

### 3.2 运行时开关

- 环境变量 `EASYHTTP_LOG=<cats>`（逗号分隔类别，`all` 全开），启动时读（native）；js/wasm 经构造参数（无 env 概念，wasm 视宿主注入而定——moonrun 有 env FFI，列为待验证）。
- 与 06 的 EventListener 分工：EventListener = **性能度量**（结构化、低开销、面向 APM）；Logger = **诊断文本**（面向人/日志系统）。同一事件源，两个消费者。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 日志门面/挂点/脱敏/开关 | **非侵入** | L1 内部 |
| @http 底座内部日志（如 Sender 状态机） | 不做 | 维持底座零日志的清爽；诊断靠 L1 事件足够 |

## 5. Target 支持矩阵

native ✅（env 开关）；wasm ⭕（构造参数，env 待验证）；js ✅（构造参数）；wasm-gc ❌（16）。

## 6. 性能影响

- no-op 默认：每事件一次函数指针判断，<10ns；生产路径零格式化（detail 惰性构造——`LogEvent.detail` 用闭包/惰性串）。
- 帧日志开启时每帧一次字符串格式化（诊断模式预期成本，okhttp 同）。

## 7. 工作量与依赖

依赖：各层成型后收口（06 同批）。**~1.5 人日**（含 H2 帧格式化占位、13 落地时补全）。

## 8. 测试方案

- 脱敏断言（含大小写变体头名）；类别过滤正确；H2 帧格式快照测试（13 联动）。
