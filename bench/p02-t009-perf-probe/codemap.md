# bench/p02-t009-perf-probe/

## Responsibility

T009 独立复核性能探针（B3，指示性 microbenchmark，非 P10 正式基准）：
1. 同一份体数据经「Bytes 定长帧」与「Stream chunked 帧」两条发送路径
   的每请求墙钟成本（µs/req）与线上字节数（bytes_per_req）；
2. `@core.Request::to_http_request` 纯函数单位成本（10^6 次循环，ns/op）。

## Design

- 转换层输出（`fixed_out`/`chunked_out`）预构造，不进发送回路；驱动
  真实 `@http.Client`，对端为 RawPeer 裸 TCP 夹具逐请求捕获 raw 长度。
- 六臂：fixed/chunked × 1KiB、64KiB 单写、64KiB=8×8KiB 分块。
- 口径护栏（B4）：机器未隔离、`@async.now()` 毫秒时钟、夹具扫描成本
  两臂共有；无对照组不得外推「性能提升 X%」。
- 标定：预热 20 + 试点 30 定 N（目标每轮 ≥500ms，钳位 [30,400]），
  6 臂先全标定再轮转 3 轮计时，降低慢漂移单臂偏置。

## Flow

`main` → 构造 8×8KiB 块及拼接的 64KiB 载荷 → 逐臂 `calibrate` →
3 轮 `bench_round`（墙钟/µs/字节）→ `bench_conversion`（带 3 自定义头
+ 多段 path+query + Bytes 体的 Request 循环 10^6 次转换，3 轮）→ done。

## Integration

- 依赖（moon.pkg）：`moonbitlang/async`、`moonbitlang/async/http`、
  `hahh9527/moonhttp/core`（经 moon.work 本地解析）、
  `hahh9527/moonhttp-bench/fixtures`（本地冻结快照）。
- 运行：`cd bench && moon run p02-t009-perf-probe --target native`
  （bench 为独立模块，仓库根构建/门禁不感知）。
- 约束：仅 127.0.0.1（宪法 IV）；代码自建（D8）；无 *_test.mbt。
