# bench/

## Responsibility

T009 独立复核（owner 2026-10-16 授权工单）用后归档的一次性探针包。
`moon.mod` 的 `source = "src"` 使本目录不参与构建：`moon check/test`
不扫描、不影响测试基线；各子目录均为独立可执行探针（各自 `main`），
无 *_test.mbt。复跑：临时复制回 `src/<原名>/`，执行
`moon fmt && moon run src/<原名> --target native`，跑完移回。
全部探针仅连 127.0.0.1（宪法 IV）、代码自建（D8）。

## Design

| 目录 | 用途 | Codemap |
| --- | --- | --- |
| `p02-t009-perf-probe/` | B3 指示性 microbenchmark：定长 vs chunked 每请求墙钟/线上字节（6 臂 3 轮）+ `to_http_request` 10^6 次纯函数成本 | [codemap.md](p02-t009-perf-probe/codemap.md) |
| `diag_probe/` | D1 chunked 64KiB 帧逐字节解剖对账；D2 RawPeer vs CheapPeer 对照分离发送方/扫描成本；D3b walk_chunks 深度阶梯实测 | [codemap.md](diag_probe/codemap.md) |
| `diag_ovf/` | D3a 11 位以上 Content-Length 经 `parse_decimal` 溢出的三型症状观测（Broken 上限 / 超时 / 空体误报或 abort） | [codemap.md](diag_ovf/codemap.md) |
| `diag_crashctl/` | 栈对照控制组：非尾自递归 1M 层，佐证 walk_chunks 尾调用优化结论（跑会故意栈溢出） | [codemap.md](diag_crashctl/codemap.md) |

## Flow

各目录互不依赖、无共享代码；共同手法为：`@core` 转换层预构造请求 →
驱动真实 `@http.Client`（或裸 `@socket.Tcp`）→ `src/fixtures` RawPeer
夹具捕获线上字节 → 逐项对账/计时并 `println` 取证。

## Integration

- 依赖面：`hahh9527/moonhttp/core`（公开转换层）、
  `hahh9527/moonhttp/fixtures`（捕获夹具）、`moonbitlang/async` 及其
  `http`/`socket` 子包；仅经公开 API 使用（宪法 I）。
- 产物归档：各探针输出复制进 T009 复核报告；本目录不进任何门禁。
