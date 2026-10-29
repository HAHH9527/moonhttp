# converge 独立复核报告（qoder 侧 `/speckit-converge`，2026-10-27）

> 角色：qoder 第三方复核方（只读 pass，未改任何治理产物与源码）。
> 触发：owner 在本会话直接调用 `.qoder/skills/speckit-converge`。
> 承接对象：`specs/006-m1-p06-redirects/`（spec.md / plan.md / tasks.md
> 为唯一意图源，`.specify/memory/constitution.md` 为最高约束）。
> 前置状态：analyze 环九轮（round1–round9，见本目录）已闭，
> `/speckit-implement` 已按 T001–T018 跑完当前 tasks.md。
> 落笔处置：本报告仅归档，T019–T022 由 opencode 于 2026-10-28 核实后
> 写入 `tasks.md` Phase 10（详见末尾「落笔实况」）。

## 1. 门禁独立复跑（本机原始输出，非转述）

| 门 | 命令 | 实测 |
| --- | --- | --- |
| native 测试 | `moon test --target native --deny-warn` | `Total tests: 270, passed: 270, failed: 0` |
| wasm 测试 | `moon test --target wasm --deny-warn` | `Total tests: 270, passed: 270, failed: 0` |
| 格式 | `moon fmt --check` | `Finished. moon: no work to do`（干净） |
| 静态检查 | `moon check --target native --deny-warn` | `ran 28 tasks, now up to date` |
| 静态检查 | `moon check --target wasm --deny-warn` | `ran 3 tasks, now up to date` |
| js（非门禁） | `moon check --target js` | **exit 1**，共 13 errors（错误码 4021×2 / 4024×2 / 4032×9），报错位置全部落在 `src/internal/fixtures/raw_peer.mbt` 与 `scripted_server.mbt`（日志内两文件引用计数 8 / 13 处）—— 与 baseline.md:26 登记的基线形态同形 |
| 接口 | `moon info` 后审 `.mbti` | 重跑无新生成变化 |

`.mbti` 对账（FR-012 / SC-008）：`git diff -U0` 过滤掉 `Int→Int32`
工具链显示漂移后——client 语义增量恰为两行
`pub suberror TooManyFollowUps derive(@debug.Debug)` ＋
`pub fn TooManyFollowUps::to_repr(Self) -> @debug.Repr`；core 与
fixtures 非漂移行数 **0**（contracts §1/§2/§3 对账通过）。

计数交叉核对：黑盒 P06 测试 23 条（`call_test.mbt`:1084–2478）、白盒
P06 测试 9 条（`follow_up_wbtest.mbt`:37–438）＝ 32 条；
`baseline.md` 运行时基线 238 ＋ 32 ＝ 270，与实测双 target 一致。
勾选态计数：`grep -c '^- \[ \]'` 当时为 0（T001–T018 全 `[X]`）。

## 2. Findings

| ID | Gap Type | Severity | Source | Evidence | Remaining Work |
|----|----------|----------|--------|----------|----------------|
| F1 | partial | HIGH | SC-004 / FR-004 / research R10「US-4（剥头/保留）」行 | 跨 host 剥头有字节级证据（`call_test.mbt`:1923 断言捕获头文本不含 `authorization`/`cookie`，含 `AUTHORIZATION` 大写变体）；同 host 保留半边仅端到端走通（`call_test.mbt`:1977-2026，注释自述「ScriptedServer 无请求头观测面」）＋白盒纯函数代位（`follow_up_wbtest.mbt`:149 P06-WB④b）。观测面实测：`ScriptedServer` 公开面无请求字节访问器（`src/internal/fixtures/pkg.generated.mbti`:80-90），`ScriptedPeer::Capture` 只回 canned 200 且单帧即关连（`raw_peer.mbt`:302-313） | 二选一由 owner 分流：①按 tasks Path Conventions 允许的「先红后绿最小扩展并逐处归因」扩 P03 观测面（同址 3xx → 捕获 follow-up 字节）；②收窄 SC-004 并回改 spec 后向下传导 |
| F2 | partial | MEDIUM | plan「性能影响」/ spec 映射表「量化归 P10」 | `docs/roadmap/M1/P10-benchmark-gate.md`:23-33 场景矩阵仅连接形态 × 请求形态 × gzip，全文无「重定向」；`docs/roadmap/deferred-items/deferred-items-m1.md` F1–F19 无对应条目 ⇒ 宪法 II「性能相关改动必须附带基准数据」的量化义务无落地对象 | 按 roadmap 文档纪律入 M1 README D 表 ＋ deferred-items 总/分结构（P06 交付状态不进 roadmap） |
| F3 | unrequested | MEDIUM | 宪法 VI / contracts §1 / plan Structure Decision | `src/client/exchange.mbt`:90 新增 `#warnings("-unused_value")`；grep 全 `specs/` 与 `docs/` 对 `unused_value` 零命中。成因：T004 后 `exchange_once` 在非测试源零调用点（仅 `call_wbtest.mbt`:366/:378/:633 白盒直调） | 按 `-reserved_keyword` 先例在 plan 例外跟踪留痕并回记 contracts §1 接缝定位，或改为不需抑制的形状（opencode 核实后按「登记性缺口」定性：成因已由源码「T017 收口注」写明） |
| F4 | partial | LOW | FR-001 / T004「桩在轮间置 cancelled」 | P06-WB④（`follow_up_wbtest.mbt`:254）实为白盒直写 `cancelled=true` 后**首轮** guard 命中，未构造「轮 k 完成、租约在场、随后取消」。行为面无泄漏：`Call::cancel` 同步 `poison_release`（`http_client.mbt`:125）承担处置；探针实测 MoonBit `errdefer` 作用域仅当前轮循环体 ⇒ 轮间 raise 不触发上一轮 errdefer（故上一轮标记的毒化收尾不会代偿） | 补真实轮间取消用例，断言裸 `CallCancelled` ＋ 连接处置；与 `baseline.md`:118-123 R9-3 的 record 级成文义务同批收 |

## 3. 摘要指标

- 检查面：FR-001～FR-012（12）、SC-001～SC-008（8）、US1–US6 验收场景
  17、Edge Cases 7。其中「HEAD/GET 带体的异常形态」spec 明示
  `implement 不为其建夹具用例`（P02 拒体组保证，`core/request.mbt`
  构造面不可达）⇒ 判为符合，不列发现。「303 后再 307」链条无专用
  用例，由单轮决策表（WB⑦ 穷举）＋ 多跳链用例（US1-prior 两跳、
  US6① 三跳、WB⑥ 21 跳）组合承载 ⇒ 不列发现。
- plan 决策 13 条（宪法门 I–VII ＋ D-1～D-4 ＋ 结构裁决 ＋ `.mbti`
  对账基线口径）；宪法原则 I–VII 全过，CRITICAL 0。
- gap type 分布：missing 0 / partial 3 / unrequested 1 / contradicts 0。
- severity 分布：CRITICAL 0 / HIGH 1 / MEDIUM 2 / LOW 1。

## 4. 已跟踪项——不发新编号（重复登记陷阱）

js 门 `moon check --target js` exit 1 不另发编号：`baseline.md`:26/:75
已登记为「基线既有、非 P06 引入」，`deferred-items-m1` F9 挂
M5/16-target-support 单点跟踪。converge 契约无 `already_tracked` 出口，
**重跑本命令仍会对该条重复登记**，按 owner 2026-10-16 墓碑口径处置。

连带措辞失实（非新任务）：原文 T018 写「`moon check --target js` 通过」，
实况口径应为「零新增 js 失败点」。已由 opencode 2026-10-28 随 Phase 10
就地订正（tasks.md:311-316 保留订正归因）。

## 5. 非任务观察（不占编号）

`attach_prior`（`follow_up.mbt`:185-197，Terminal 返回位点 :249）对**每次**
execute 都重建终态 Response（`to_http_map` → `from_http` 重拆并头），
即便 prior=None 也重建。`data-model.md` 实体 1 伪代码
（`return with_prior(response, prior, keep_body=true)`）即此形 ⇒ 不算偏离
意图，故不列 finding。头值逗号拆分/合并的往返在本包是幂等的（P05 管线
`exchange.mbt`:149-155 已经历同一条 `from_http` 路径），顺序失真属已跟踪
的 F11。观察价值在于与 F2/T020 咬合：量化一旦落到 P10 场景即暴露该
每请求一次额外出入。

## 6. 落笔实况（2026-10-28 只读核对）

- `tasks.md`:320 起为 `## Phase 10: Convergence（converge 欠账收口）`，
  节头带 4 条发现的承接口径、js 重复登记规避（明写「重跑会对其重复
  登记」）、非任务观察不占编号三块——本报告 §4/§5 的口径已在产物内。
- T019 / T020 / T021 / T022 对应 F1 / F2 / F3 / F4，编号接 T018，未触碰
  任何既有任务；F3 按「登记性缺口」定性微调。
- 插落位为 Phase 9 之后、`## Dependencies & Execution Order` 之前（保持
  phase 节相邻，非文件最末），且依赖图已同步补 Phase 10 一行：
  `T020 ∥ T021（文档面）；T019/T022 代码面按 owner 分流串行`。
- 勾选态计数（落笔后）：`[X]` 18 / `[ ]` 4；
  `grep -rnP '[\x00-\x08\x0b\x0c\x0e-\x1f]|\x09' specs/006 下全部 md` 为空。
- 后续：T019–T022 属 implement 现场工作，非本轮收敛；本包 Phase 1–9
  已收口（六门双绿 ＋ 契约对账），P06 交付判据以 specs/006 产物为准。
