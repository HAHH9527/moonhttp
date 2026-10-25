# P05 收尾归档（T014–T017，2026-10-25）

## 1. `.mbti` 三面对账结论（T014，FR-014/SC-007/I-7）

- **`src/client` = contracts/call-api.md §1 恰等**：`placeholder()` 保留
  （P6 延续，删除评估留后续收口片）；`HttpClient::new/new_call`；
  `Call::execute/cancel/is_cancelled`；`CallCancelled`/`CallStateError`。
  计划外项仅两 `to_repr`（[0079] 配套 `pub extend … Debug::{to_repr}`，
  P01 HeadersError 先例同款）；**无** enqueue/拦截器/builder/request
  访问器/exchange_once/BodyBridge/1xx 回调参数。命名全 snake_case。
- **`src/core` = §2 且仅此 + 一处已登记偏差**：`ResponseBody::stream` 增
  `on_dispose?` + `ResponseBody::dispose` 恰为 §2；P01 既有面零 diff；
  偏差＝`BodySource::Stream` 回调 async 化（见 research.md R9 偏差 1，
  归因：同步回调语言规则下无法驱动 async 写入，US-1④ 不可表达）。
- **`src/internal/fixtures` 非零 diff，逐处归因**：InterimThen/mount_interim
  （FR-010）；Truncated/mount_truncated（FR-011/FR-005 注入缝）；
  expect_request_line（`method` 保留字构造缝）。明细见 research.md R9。

## 2. F-8 核实结论（T002）

不支持（单请求内 1xx→200 超出 ResponseScript 模型）→ 已按兜底最小扩展，
`P05-FIX①` 双 target 绿。明细见 research.md R6「F-8 核实结论」。

## 3. 六门结果（T015，最终轮先 `moon clean`）

| 门 | 结果 |
| --- | --- |
| `moon check --target native --deny-warn` | ✅ |
| `moon check --target wasm --deny-warn` | ✅ |
| `moon test --target native --deny-warn` | ✅ Total tests: **231**, 231 passed（基线 191 + 新增 40；静态 233 − 2 条 `#skip` 长跑） |
| `moon test --target wasm --deny-warn` | ✅ Total tests: **231**, 231 passed |
| `moon fmt --check` | ✅ |
| `moon info` 审视 | ✅ 工作树零 diff（对账结论见 §1） |

- `-p` 全包名口径执行过分包验证（每类过滤器 `Total tests:` 非 0，假绿警示落实）。
- SC-006：P05 全部测试仅触 `127.0.0.1`/夹具 `port()`；grep 命中的
  `example.com` 均为 P01 既有的 URL 解析纯函数用例（不发网络），非外网端点。
- 弃用面零引用：`is_cancellation_error`/`with_cancellation_handler`/`Timer`
  /`TaskCancelled` 别名零引用；`protect_from_cancel` 代码零使用（仅注释
  提及白名单，I-6/T009⑩ 判据）。

## 4. js 非门禁项（T016，D14/F9）

`moon check --target js` **失败**——失败点全部位于 P03 既有
`src/internal/fixtures/raw_peer.mbt`（js 后端无 socket 面）；**P05 基线
（stash 后干净树）复测同样失败**，非本包引入。P05 代码零 `#cfg(js)` 分支
（R7 口径落实）。node 冒烟不可行（夹具层即不编译）——登记欠账，随 M5
js 收口处理。

## 5. FR/SC 覆盖对账（映射表核验，无缺项）

FR-001～015、SC-001～007 逐条对映 tasks.md 映射表全部在场并双 target 绿；
不变量 I-1～I-7 对映 T011/T006+T012/T005+T008+T009/T010/T004+T008/T007+T009
/T014 全部落位。

## 6. 宪法自查（随 PR 记录）

- **I 非侵入底座**：全程仅 `@async`/`@http` 公开 API；零 fork/vendor；上游
  零改动。在途读取消悬挂为上游缺口，已登记欠账（R9 偏差 3），未改上游。
- **II 性能优先**：折叠缓存机制级交付（SC-004 计数+字节级）；取消通道
  O(1) 标记；量化归 P10。
- **III OkHttp 对齐**：Call 一次性/取消判别/无闸门并发沿映射表；显式差异
  （dispose 异步收尾、无 GC 泄漏检测的租约滞留文档化）均已在 plan 登记。
- **IV 测试先行**：每任务元测试先红后绿；护栏/落笔即绿判据（WB⑩、US1⑦
  文档部分）在测试头注显式标注。
- **V Target 策略**：native/wasm 双绿；js 非门禁失败为 P03 既有、欠账登记。
- **VI 简洁与接口纪律**：三处偏差/扩展全部显式归因登记（research.md R9）。
- **VII 中文表达**：注释/文档/提交全中文。

## 7. 持续盯防（plan 风险 R1/R2 的收口结论）

- 取消收尾无 async 操作：I-6 白名单在 execute 注释块 + body_bridge
  errdefer 落实，WB⑩ 可执行代理判据双 target 绿。
- body 阶段 cancel 的 lease 置 None 时序：I-3「处置完成即置 None」单点在
  `Call::poison_release`/`release_lease`（body_bridge.mbt）；WB⑨ 迟到
  cancel 竞争双 target 绿。

## 8. 欠账登记

1. 在途读 + 跨协程关连悬挂（上游缺口）——在途读取消直驱形态待上游澄清
   后回补（R9 偏差 3）。
2. js 夹具编译失败（P03 既有）——随 M5 js 收口。
3. `placeholder` 保留，删除评估留后续收口片。
