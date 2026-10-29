# P06 动工前基线（T001，只读测量）

- 日期：2026-10-27 ｜ 执行者：implement（工单⑫，owner 已批准）
- 工具链：moon 0.1.20261023 (3778465 2026-10-23)
- 基线底座：git HEAD = `8c775109e583eeecf1b25ecba2c5d4295ce6725c`
  （P05 骨架提交态；plan.md:120-132 W2 口径——`.mbti` 对账基线 =
  git HEAD 提交态）

## 测试计数

- 静态计数（`Select-String '^\s*(async\s+)?test\s'`，`*_test.mbt` +
  `*_wbtest.mbt`）== **240**（与 tasks.md T001 预记一致，无漂移）。
- 差额归因：`src/client/pool_longrun_wbtest.mbt` 含 2 条 `#skip` 长跑
  条目（P03 C5 裁决，默认六门排除）⇒ 运行时 238 = 240 − 2。
- 运行时基线（`moon test` 实测）：
  - native：`Total tests: 238, passed: 238, failed: 0`
  - wasm：`Total tests: 238, passed: 238, failed: 0`

## 六门基线

| 门 | 命令 | 结果 |
| --- | --- | --- |
| 1 接口/格式 | `moon fmt --check` + `moon info` | fmt 干净（exit 0）；info 重跑仅复现既有 3 份 `.mbti` 漂移（见下） |
| 2 native 测试 | `moon test --target native --deny-warn` | 238/238 全绿 |
| 3 wasm 测试 | `moon test --target wasm --deny-warn` | 238/238 全绿 |
| 4 js 编译 | `moon check --target js` | **失败（基线既有，非 P06 引入）**：13 errors 全部位于 `src/internal/fixtures/raw_peer.mbt` / `scripted_server.mbt`（js 后端无 socket/ServerConnection 面）。P05 archive.md §4 同款登记（P05 基线复测同失败），非门禁欠账随 M5 收口。T018 复核口径 = P06 增量零新增 js 失败点 + 零 `#cfg(js)` 分支 |
| 5 覆盖（辅助） | `moon coverage analyze` | 收口期按需（quickstart 门5 辅助项） |
| 6 宪法自查 | spec 映射表 | 差异记录以 spec「宪法合规口径」表为载体，收口对账 |

另：`moon check --target native/wasm --deny-warn` 双双通过（32 tasks，
零警告）。

## `.mbti` 快照（W2 口径：以 git HEAD 为准，工作区漂移不入账）

- 工作区 3 份 `pkg.generated.mbti`（client/core/fixtures）现处 M 态，
  diff 全量为 `Int→Int32` 签名改写（client `Address::hash/new(port~)/
  port`、`ConnectionPool::new/per_host_total/stale_evictions` 等）——
  本地工具链 `moon info` 再生成显示差异（round7 W2 / round8 W2 归因，
  本机 moon 0.1.20261023 > plan 所钉 0.1.20261012 佐证成立）。实测
  `git status --porcelain` 无任何 `.mbt` 伴随改动。
- 该漂移不随 P06 交付、不入账、不触碰、不提交（plan.md:120-132）。
- HEAD 快照指纹（SHA256，供 T017 收口对账）：
  - `src/client/pkg.generated.mbti` =
    `B95F6CCCB752D13D1A19C2821D54C274BA344D6159240128A4CFE5590CBAC61F`
  - `src/core/pkg.generated.mbti` =
    `83F0539B3979841EB2307591E5F8D62A9C4AA9C577F91D41C8B2BF0A7880AEC4`
  - `src/internal/fixtures/pkg.generated.mbti` =
    `B2A1F2A91711632443D6E3A99E166F745CA44F6E3B7C43ACBEBA5271E840CF1B`
- client HEAD `.mbti` 公开面要点（P05 冻结面）：`placeholder`/
  `HttpClient`/`Call`/`ConnectionPool`/`Address`/`Lease` + 错误两变体
  `CallCancelled`/`CallStateError`（各带 to_repr extend）——P06 期望
  增量 = 且仅 = `TooManyFollowUps` 两件套（contracts §1）。

## 实况对账注记（Q-B3 / T003 直调点，落笔前已核）

- `exchange_once` 实况签名：`async fn Call::exchange_once(self : Call)
  -> @core.Response`（exchange.mbt:78，读 `self.request`）；
  `exchange_with_lease(self, lease : Lease)`（exchange.mbt:91）。
- `call_wbtest.mbt` 内 `exchange_once` 字样 5 处，实际直调点
  **3 处**（:366/:378/:633——WB⑧ 两处 + US4① 一处），另 2 处为
  注释与测试名。T003 适配以实况调用点为准。

---

# T017 收口对账（2026-10-27，implement 收尾）

## 六门终态

| 门 | 命令 | 结果 |
| --- | --- | --- |
| 1 接口/格式 | `moon info && moon fmt`（+`fmt --check`） | 干净（exit 0） |
| 2 native | `moon test --target native --deny-warn` | **270/270 全绿** |
| 3 wasm | `moon test --target wasm --deny-warn` | **270/270 全绿** |
| 3b 静态检查 | `moon check --target native/wasm --deny-warn` | 双双干净 |
| 4 js（非门禁） | `moon check --target js` | 与基线同形：13 errors 全在 P03 夹具两文件（raw_peer/scripted_server——js 后端无 socket 面，P05 archive §4 同款欠账随 M5）；client 零 `#cfg(js)` 分支、零新增 js 失败点（T018 复核 ✅） |
| 5 覆盖（辅助） | `moon coverage analyze > uncovered.log` | 工具对 `src/core/request.mbt` 报 lexical parse 限制（辅助工具面）；决策表覆盖由 P06-WB⑦ 穷举矩阵实质承载（每格断言） |
| 6 宪法自查 | spec 映射表 | 四处显式差异（C1 剥 Cookie/D7 408 组/显式变体/js 形态）以 spec「宪法合规口径」表为记录载体，零回改语义 |

P06 新增测试 32 条（黑盒 23 + 白盒 9）：238 基线 + 32 = 270。

## `.mbti` diff 审视（SC-008/FR-012 对账）

- client vs git HEAD：**语义增量 = 且仅 = `TooManyFollowUps` 两件套**
  （`pub suberror TooManyFollowUps derive(@debug.Debug)` +
  `pub fn TooManyFollowUps::to_repr(Self) -> @debug.Repr`）——恰为
  contracts §1；其余 diff 全为既有 `Int→Int32` 工具链漂移（W2 口径
  不入账、不触碰、不提交）。
- core / fixtures vs git HEAD：**非漂移行 = 0**（contracts §2/§3 零
  diff ✅）。
- **（2026-10-28 review 修复批订正——上两条在交付态不成立，原文按
  登记保留）**：①本节断言写于 T019 之前；交付态 fixtures `.mbti`
  含 T019 `captured_request_heads`（非漂移语义增量，contracts §3
  第一次登记例外）与 review 修复批 `Truncated(ResponseScript, Bool)`/
  `mount_truncated derive_close?`（contracts §3 第二次登记例外），
  「非漂移行 = 0」为假。②client `.mbti` 必随 P06 交付
  `TooManyFollowUps` 两件套；且 `moon info` 为宪法工具链规定收尾步，
  本机再生成必然重写 `Int→Int32` 漂移行——「不提交」在交付态不可
  达。交付态口径：三份 `.mbti` 漂移 + 语义增量随 P06 提交，宪法 VI
  「公开面变化必须是有意识的决定」以 plan「`.mbti` 对账基线口径」
  订正节 + contracts §3 两次登记例外为决定载体。
- 公开面清单核验：`TooManyFollowUps`/`CallCancelled`/`CallStateError`
  三变体 + to_repr extend；`Response::prior` 访问器（P02 既有 ：160，
  R9-2 换算锚点）；无计划外公开项（FR-012 冻结面一致）。

## SC-001～SC-008 证据测试名

| SC | 证据 |
| --- | --- |
| SC-001 | P06-US1①②④⑤ / P06-US2①②③ / P06-US3①（三形态）② / P06-US4①② / P06-US5①①续②③ / P06-US6①②补①补② 全绿（双 target）；决策表每行 ≥1 用例由 P06-WB⑦ 穷举矩阵承载 |
| SC-002 | P06-US5①（21 跳链）/ P06-US5①续（A→B→A）/ P06-WB⑥（20 follow-up、gen 20、fold 21）——`err is TooManyFollowUps` 判别 |
| SC-003 | P06-US6①（3 跳同 host 连接数 1）/ P06-US6②（跨 host 干净回池复用 + 新建 +1，双实例计数——W1 方案 B） |
| SC-004 | P06-US4①（跨 host 剥双头，AUTHORIZATION 大写变体钉 remove 不敏感）/ P06-WB④b（rewrite_headers 直驱：同 host 保留 / 跨 host 剥除双向）/ P06-US4②（同 host 保留链路走通） |
| SC-005 | P06-US1-prior（链深 2、回溯保序、条目 body=None）/ P06-US1①②④⑤（链长 1） |
| SC-006 | P06-US6①（第 4 请求干净流、1KB 排干）/ P06-WB⑤（中间响应零事件：consumed/dropped 双 false） |
| SC-007 | 全部 32 条测试仅触 P03 loopback 夹具（ScriptedServer/ScriptedPeer，127.0.0.1），零外部网络 |
| SC-008 | 本文件「.mbti diff 审视」节（两件套 + 漂移不入账） |

DoD 对账：①US 全场景双 target 绿 ✅；②两变体进 `.mbti` 且有 `err is`
判别测试（WB①b/US5①）✅；③info/fmt 干净 + diff 审视 ✅；④语义差异
表保留于 spec 未回改 ✅。

## R9-1/R9-2/R9-3 记录级残留换算对账（勿扩面）

- **R9-1**（round8 日志行号登记 ±1 精度）：登记性质，无产物改动需求；
  本轮引用一律以磁盘实测行号为准，未复用该登记表。
- **R9-2**（round7 三处 mbti 行号漂移）：implement 期实际引用按工作区
  实测换算——`HttpClient::new_call`=mbti:41、`Response::from_http`=:158、
  `Response::prior`=:160（结论不变、引用位已校准）；归档件不回改。
- **R9-3**（五条授权外 INFO：六门成员双轨/FR-001 轮间取消租约处置未
  成文/C1 编号双指/R7 21 跳注记/checklists 勾选口径）：按工单「勿扩面」
  维持记录级，未处置、未回改任何产物。其中「FR-001 轮间取消租约处置」
  实况：轮间取消时租约若在场由循环顶 guard 后的轮级 errdefer /
  P05 cancel 通道毒化收尾（body_bridge.poison_release 单点），行为面
  已由 P05-WB⑥/US3③ 与 P06-WB④ 覆盖，成文义务仍留 record 级。
  2026-10-28 T022 已闭合——「FR-001 轮间取消租约处置」成文于 follow_up.mbt 循环顶 guard 注释，行为用例 P06-WB④c（轮 k 完成租约在场 → cancel → 裸 CallCancelled + 毒化连接不回池）。
- R9-4（取证边界）：无新证据，维持原判。

## implement 期实现先行/偏差登记（宪法 IV 审计面）

1. **T006**：首跑红（GET 链二跳需保持行）→ 按 T007 保持行落地后同批
   转绿；两任务红侧均先于实现实测留痕，无倒装。
2. **T010**：三形态/非法回退首跑即绿（T005 resolve 门实现先行）——
   tasks I2 注记情形，实测归因登记；唯一红为我方计数断言订正（[3]→[2]，
   末跳跨 host），非实现缺口。
3. **T012**：三场景首跑即绿（`drain_intermediate` 于 T006 为打通链路
   先落最小形态；T012 交付其测试与带体场景）。
4. **T013 US6②**：首跑即绿（跨 host 换租由 T004 ensure_lease 分支
   承载）；补①（同 host close）红→绿真实闭合。
5. **T015**：首跑即绿（T002 Terminal 行实现先行，tasks 注记情形）。
6. **T016**：矩阵红测钉死真实缺陷（跟随集范围 guard 误纳 304/305/306
   ——GET/HEAD+304+Location 误跟随）→ 精确码集修正后全绿；WB①/US5②③
   此前未暴露系其用例未覆盖该交叉格。
7. **T004 WB③**：阶段前提（Terminal-only 骨架）随决策表展开失效，
   测试前提改用恒 Terminal 的 200 重写（断言结构不变，非迁就实现）。
8. **夹具适配**：`serve_n(n)` 语义 = 连接数（非请求数）——两起挂起
   （US1-prior 首版 serve_n(3)、US6② 首版多余 s2 serve_once）均系
   测试侧夹具误用，订正后消解；零夹具扩展（R7 零扩展基线成立）。
   **（2026-10-28 review 修复批订正）**：零扩展随后被打破——T019
   `captured_request_heads`（+31 行）与本批 `mount_truncated
   derive_close~` 两次登记性例外（contracts §3），research R7 订正段
   同款口径。

---

# review 修复批对账（2026-10-28，open-code-review delegate 模式）

- 审查范围：34 文件（8 代码/Schema 逐行 + 24 文档对账）；结论逐条
  核对后修复，全清单见 tasks.md T023。
- 六门复跑：native/wasm 各 **276/276** 全绿（272 = 238 基线 + P06 32
  条 + T019 补 2 条；本批新增 4 条：P06-WB⑧ / P06-WB④d /
  P06-US6 补③ / P06-US3④，修复与断言同批落地的首跑即绿归因已入
  各测试头注释）；`moon check --target native/wasm --deny-warn`
  干净；`moon info && moon fmt` 干净；js `moon check --target js`
  13 errors 与基线同形（全在 P03 夹具 raw_peer/scripted_server 两
  文件，零新增失败点）。
- `.mbti` 交付态（替换本文件 T017 节「不提交」口径，订正见上节）：
  client = `TooManyFollowUps` 两件套 + `Int→Int32` 工具链漂移；
  core = 仅 `Int→Int32` 漂移（源码零 diff）；fixtures = `Int→Int32`
  漂移 + `captured_request_heads` + `Truncated(ResponseScript, Bool)`
  + `mount_truncated derive_close?`——全部为登记在案的有意识决定。
- 未采纳（审查 Low 项择一不改）：call_test.mbt 约 250 行近重复场景
  的表格驱动压缩——重构性去重非缺陷修复，留后续 simplify 批次。

