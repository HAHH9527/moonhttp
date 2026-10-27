# bench/diag_ovf/

## Responsibility

T009 复核追加诊断 D3a：观测 11 位以上 Content-Length 经
src/fixtures/frames.mbt `parse_decimal`（Int32）的溢出实际症状——
只回报症状，不做修复。目标症状空间：Broken「超出夹具上限」/
NeedMore→超时 note / Complete+空 body 误报 / slice 越界 abort。

## Design

- 三个用例各自独立的 `RawPeer` 生命周期，互不污染；高危例（可能触发
  进程级 abort）置于最后，保证前两例结果先落盘：
  - 例1 `99999999999`（11 个 9）：溢出 wrap 后为正且大于夹具上限；
  - 例2 `00000000100`（前导零 11 位）：无溢出，声明 100 而体仅 3；
  - 例3 `30000000000`：溢出 wrap 后为负（高危）。
- 探针内自建 `ascii_bytes` 做头部编码；不修改 fixtures 任何代码。

## Flow

`main` → 逐例 `probe_case(tag, cl_line, timeout_ms)`：启动 RawPeer →
task group 并发 `capture_one` 捕获 → 裸 `@socket.Tcp::connect` 发送
带指定 CL 行的 POST 头 + 3 字节体 → `read_all`/close → 打印
complete/chunked/body_len/raw_len/note/head 保留情况。末行 `done`
缺失即说明例3 触发了进程 abort。

## Integration

- 依赖（moon.pkg）：`moonbitlang/async`、`moonbitlang/async/socket`、
  `hahh9527/moonhttp-bench/fixtures`（RawPeer 捕获夹具，本地冻结快照）。
- 运行：`cd bench && moon run diag_ovf --target native`（bench 为独立模块，
  仓库根构建/门禁不感知）。
- 约束：仅连 127.0.0.1（宪法 IV）；无 *_test.mbt。
