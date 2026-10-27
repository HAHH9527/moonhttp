# bench/ —— 一次性探针归档（独立可运行模块，不进仓库根构建）

本目录是 T009 独立复核（owner 2026-10-16 授权工单）用后归档的一次性探针包，
现为**独立 moon 模块**（`bench/moon.mod` + `bench/moon.work`）：

- 本地依赖主模块：`moon.work` 声明成员 `./`（bench 自身）与 `..`
  （`hahh9527/moonhttp`），成员间按模块名本地解析（import 中的 `@version`
  仅占位，实际取本地源码）。新 `moon.mod` 格式不支持 path 依赖，workspace
  是官方指定的本地依赖方式。
- 仓库根不感知：`moon.work` 位于 bench/ 内、不向上泄漏，根目录
  `moon check/test/fmt` 不扫描本目录（根模块 `source = "src"` 同样不覆盖），
  126 测试基线与门禁不受影响。
- 夹具快照：`fixtures/` 冻结自主模块迁移提交 `327ff7e` 父版本的
  `src/fixtures/{raw_peer,frames}.mbt`（探针归档时的 RawPeer 形态）。
  主模块 fixtures 此后迁入 `src/internal/fixtures` 并演进为 ScriptedPeer，
  且跨模块禁 import internal 包，故就地冻结以保探针可复跑。

| 目录 | 用途 | 来源 |
| --- | --- | --- |
| `p02-t009-perf-probe/` | L2 杠杆 microbenchmark（定长 vs chunked 端到端 + to_http_request 10^6） | 2026-10-16 复核 B3（原 src/perf_probe） |
| `diag_probe/` | D1 字节账解剖 / D2 CheapPeer 对照 / D3b walk_chunks 深度阶梯 | 2026-10-16 复核追加诊断 |
| `diag_ovf/` | D3a parse_decimal Int32 溢出三型症状观测 | 同上 |
| `diag_crashctl/` | 栈对照控制组（尾/非尾递归各 1M 层；非尾跑会故意栈溢出） | 同上 |

再跑方法：`cd bench && moon run <目录名> --target native`（如
`moon run diag_ovf`），无需再复制回 `src/`。全部探针仅连 127.0.0.1
（宪法 IV）、代码自建（D8）、无 *_test.mbt。
