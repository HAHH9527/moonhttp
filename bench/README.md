# bench/ —— 一次性探针归档（不参与构建）

本目录是 T009 独立复核（owner 2026-10-16 授权工单）用后归档的一次性探针包。
moon 默认不把 `bench/` 当作包搜索路径（`moon check/test` 不扫描、不影响
126 测试基线；`moon.mod` 按工单禁改，故不注册该目录）。

| 目录 | 用途 | 来源 |
| --- | --- | --- |
| `p02-t009-perf-probe/` | L2 杠杆 microbenchmark（定长 vs chunked 端到端 + to_http_request 10^6） | 2026-10-16 复核 B3（原 src/perf_probe） |
| `diag_probe/` | D1 字节账解剖 / D2 CheapPeer 对照 / D3b walk_chunks 深度阶梯 | 2026-10-16 复核追加诊断 |
| `diag_ovf/` | D3a parse_decimal Int32 溢出三型症状观测 | 同上 |
| `diag_crashctl/` | 栈对照控制组（尾/非尾递归各 1M 层；非尾跑会故意栈溢出） | 同上 |

再跑方法：把对应目录临时复制回 `src/<原名>/`，`moon fmt && moon run src/<原名> --target native`，
跑完移回本目录。全部探针仅连 127.0.0.1（宪法 IV）、代码自建（D8）、无 *_test.mbt。
