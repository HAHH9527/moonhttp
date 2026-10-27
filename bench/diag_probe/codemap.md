# bench/diag_probe/

## Responsibility

T009 复核追加诊断探针（约 850 行，跑完归档）：
- D1 —— 64KiB chunked 线上帧逐字节解剖对账（头行/大小行/块尾 CRLF/
  终止块/帧后多余字节，误差应为 0）；
- D2 —— RawPeer（夹具全量扫描）vs 自建 CheapPeer（O(1) 完成判定）
  同臂对照，分离发送方成本 / 对端扫描成本 / 连接底座；
- D3b —— `walk_chunks` 自递归深度阶梯实测（配 diag_crashctl 栈对照）。

## Design

- 字节域工具全部自建（D8）：`find_sub`/`header_value_span`/
  `parse_dec`/`parse_hex`/`dissect`（对捕获 raw 做与夹具同口径的帧
  解剖，只统计不改字节）；载荷用 `make_block_printable` 保证仅可打印
  字母，排除 `b"0\r\n\r\n"` 假阳性。
- 三种转换层输出预构造：`fixed_out`（Bytes 定长体）、`chunked_out`
  （Stream 体 → 转换层删 CL，上游落 TE: chunked）、`get_out`（无体地板臂），
  经 `@core.RequestBuilder` 构造后 `to_http_request` 驱动真实 `@http.Client`。
- CheapPeer：accept → 8KiB 循环读 → 定长计数 / chunked 5 字节后缀
  （含跨读边界）/ 无体即帧三种 O(1) 判停，不做 walk_chunks 与 payload 重组。
- D3b 阶梯：6B 块×10k（对照）/ 6B×100k（预期夹具假 Broken，取证）/
  256B×32k（深 32k 递归安全证明）；客户端 64KiB 分片写 + `read_all`。

## Flow

`main` → `d1_ledger`（fixed 对照 + chunked 解剖对账，返回捕获 raw）
→ `d2_arms`（6 臂标定 `calibrate`（预热 15 + 试点 25 → 每轮 ≥500ms，
钳位 [30,400]）→ 3 轮轮转计时 + walk/to_bytes 微基准）→ `d3b_tco`
（三档深度阶梯，600s 超时捕获）→ done。

## Integration

- 依赖（moon.pkg）：`moonbitlang/async`、`moonbitlang/async/http`、
  `moonbitlang/async/socket`、`hahh9527/moonhttp/core`（转换层，经
  moon.work 本地解析）、`hahh9527/moonhttp-bench/fixtures`
  （RawPeer/CapturedRequest，本地冻结快照）。
- 运行：`cd bench && moon run diag_probe --target native`（bench 为独立
  模块，仓库根构建/门禁不感知）。
- 约束：仅 127.0.0.1（宪法 IV）；无 *_test.mbt。
