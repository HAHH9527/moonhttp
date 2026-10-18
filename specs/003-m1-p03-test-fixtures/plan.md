# Implementation Plan: 可控服务端测试基建（M1-P03）

**Branch**: `003-m1-p03-test-fixtures` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-m1-p03-test-fixtures/spec.md`
（含 2026-10-18 Clarifications D1–D5）

**Note**: owner 批准自主规划（不提问、按证据裁决）；research.md 承载全部工具链
实测证据，本文引用不重复。

## Summary

交付 moonhttp 自有的可编程本地测试服务端夹具库，宿主迁至
`src/internal/fixtures`（C1 裁决，toolchain internal 规则强制隔离）：
第 1 类基于 `@http.Server` 的声明式路由编排服务端（B-01～B-06、B-08），
第 2 类基于 `@socket` 的程序化裸 TCP 对端（B-09～B-13），外加端口分配与
生命周期/超时辅助（B-14/B-15）。同步完成五处继承缺陷回归（FR-006～FR-010：
增量帧扫描状态机、数值封顶累加、重复 CL 判畸形、断言辅助参数化），全部行为
以包内自证元测试交付（FR-002），native + wasm 双绿为质量门（宪法 V）。

## Technical Context

**Language/Version**: MoonBit，moon 0.1.20261012（`--deny-warn`/`fmt --check`/
`moon test -p/-f` 旗标已核证，research.md P-h）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（钉 0.22.x，registry 版本，
宪法技术约束）；仅用 `@http`/`@socket`/`@async` 公开 API
（`Server` mbti:141-171、`Tcp/TcpServer` mbti:45-78、`now()` 根包 mbti:26、
`with_timeout_opt` mbti:50、`with_task_group` mbti:46）

**Storage**: N/A（纯内存夹具）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；自证元测试即
本包测试（spec 测试方案口径）；命名 `P03-Bxxⓝ 描述` 沿用既有风格

**Target Platform**: native + wasm（moonrun/WASI 宿主）双绿为门；js 只承诺
API 层单测不承诺夹具行为（D1/E1）；wasm-gc 排除（README D9）

**Project Type**: library（模块内测试支撑包，pkgtype `library`——该种类不存在
「test」，research.md P-d）

**Performance Goals**: SC-003（8MB 捕获 ≤2s 且 2MB/8MB 耗时比 ≤5，对照缺陷
实测约 10.2s）；无热路径交付物（宪法 II 冷路径简洁优先）

**Constraints**: 全部夹具仅监听 loopback（FR-003）；每操作超时保护
（FR-004）；不搬上游测试资产（D8）；不为 RST 自写 C/FFI 绑定（见宪法对照）

**Scale/Scope**: 1 个内部包（迁移 + 扩展），6 个测试文件，B-01～B-15 行为面
（B-07 缺口），FR-001～FR-015

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过，含一项显式否决**：全部设计仅经 `@http`/`@socket`/`@async` 公开 API（取证锚点见 research.md R2/R3）；不 fork/复制/vendor 上游源码；不搬 `test_programs`/`examples`/`mio` 资产（D8，手法仅参考 `src/internal/test_util` 的断言辅助范式，代码自建）。**显式否决**：为获得 RST/SO_LINGER/shutdown 而在本项目自写 `extern "C"` 绑定——该做法等于给上游缺口私自补能力、仅 native 可用、破坏零 fork 原则，本 plan 不纳入实施路径。若 owner 未来认为必要，属**需人工批准的候选方案**（须同步走宪法 I 的上游 PR 回馈评估），当前无此必要：B-10 已按 D2 裁决改为 close+观测清单，无任何场景被该缺口阻塞 |
| II 性能优先 | 通过：测试基建属冷路径，简洁优先（宪法 II 但书）；FR-010/SC-003 仅为夹具可用性时延约束，不做吞吐优化 |
| III OkHttp 语义对齐 | 不适用（本包为测试基建，不落客户端语义；canned 响应字节取自上游写出形态取证，属对底座行为的观测而非对齐目标） |
| IV 验收场景与测试先行 | 通过：每种行为一个自证元测试（FR-002），映射表见下；断言优先 `assert_eq`/`assert_true`；全部夹具仅 loopback（FR-003，`Addr::parse("127.0.0.1:0")` 单点收口） |
| V Target 策略 | 通过：native ≥ wasm 双绿为门；js 未验证（D1/E1 已核实不可监听）；wasm-gc 排除；target 矩阵已在 spec 显式标注 |
| VI 简洁与接口纪律 | 通过：C1 迁移是零抽象路径变更；单一内部包（不拆子包，三行相似代码优于过早抽象）；`.mbti` 逐次审视入六门（internal 包 `.mbti` 非对外承诺，泄漏风险面清零） |
| VII 中文表达 | 通过：注释/文档全中文；commit 走 Conventional Commits 中文描述 |

**Phase 1 复核**：设计落定后无新增违宪点；唯一需持续盯防项＝不为实现便利
引入 native-stub（wasm 双绿门会天然拦截）。

## Project Structure

### Documentation (this feature)

```text
specs/003-m1-p03-test-fixtures/
├── spec.md                    # 已含 Clarifications D1–D5
├── plan.md                    # 本文
├── research.md                # C1 探针证据（P-a～P-h）+ 全部决策
├── data-model.md              # 实体/状态机/常量校准
├── contracts/
│   ├── fixtures-api.md        # internal/fixtures 契约面
│   └── wire-observations.md   # FR-015 观测清单契约
├── quickstart.md              # 六门 + 分场景验证命令
└── checklists/requirements.md # 16/16（specify 阶段产物）
```

### Source Code (repository root)

```text
src/
├── internal/                  # 新增 internal 段（toolchain 可见性规则，R1）
│   └── fixtures/              # ← 自 src/fixtures 整体迁移（C1 裁决）
│       ├── moon.pkg           # 依赖不变：moonbitlang/async + async/socket
│       ├── frames.mbt         # 判停内核：重写为 FrameScanner 增量状态机（R4.1/4.2/4.3）
│       ├── raw_peer.mbt       # → 扩展为 ScriptedPeer（PeerProgram 程序化）
│       ├── raw_peer_test.mbt  # 既有自证 ①–⑦ 保留（路径注释随迁更新）
│       ├── scripted_server.mbt    # 新：ScriptedServer + ResponseScript（第 1 类）
│       ├── scripted_peer.mbt      # 新：PeerProgram/CutPoint 编排（B-09～B-12）
│       ├── frames_scan_wbtest.mbt # 新：白盒 FR-006/007/008
│       ├── scripted_server_test.mbt # 新：US-1 + B-05/B-06/B-08
│       ├── scripted_peer_test.mbt   # 新：US-2
│       ├── fr015_observation_test.mbt # 新：FR-015 观测清单生成
│       └── sc003_sc004_test.mbt     # 新：SC-003/SC-004 + FR-009 三形态
└── core/
    └── moon.pkg               # 唯一构建图内消费方：导入路径改 1 行（fixtures → internal/fixtures，for "test"）；bench/ 三归档探针 import 随迁移失效（已知不改，见 tasks T002）
    └── wire_form_test.mbt     # assert_captured_frame 换参数化辅助（缺陷 5 回归落点）
```

**Structure Decision**: 单一内部包承载两类夹具+辅助（不拆子包：宪法 VI，
消费方仅 core 测试与包内元测试）；`test_programs` 式 src 外目录被 P-e 探针
排除（不进包搜索路径，无法承载 `moon test` 元测试）。

## C1 裁决（摘要，全证据见 research.md R1）

**迁 `src/internal/fixtures`，包类型保持 library。** 依据：internal 可见性由
工具链编译期强制（P-a 跨模块拒绝 / P-b 同模块包通过 / P-c 黑盒测试通过），
是唯一真实生效的按包隔离手段；`pkgtype` 无 test 种类（P-d）、src 外目录不进
构建图（P-e）、发布面原样携带测试文件与 internal 包（P-f）、`moon.mod
private` 模块级且未支持（P-g）。另一条（原位公开包）的代价＝公开面永久
增长 + 更晚收紧的更大 churn；上游手法对齐 `src/internal/test_util`（D8）。
收紧路径：本裁决即收紧终态，无需后续动作。

## 五处继承缺陷 → 修复手法 → 证明元测试（一句话版，细则 research.md R4）

| 缺陷（锚点） | 修复手法 | 证明元测试 |
| --- | --- | --- |
| 1 相位假 Broken（frames.mbt:270-275） | 大小行改行缓冲＋`max_size_line_bytes` 自身长度上界，废弃绝对偏移充当上界 | `frames_scan_wbtest`：>64KiB 流 × 劈中大小行的切分相位 ⇒ 完整收完 |
| 2 Int32 溢出三型（frames.mbt:195-217/236-258） | 封顶累加，>16MiB 即时 Broken，回绕在构造上不可能 | `frames_scan_wbtest`：CL=99999999999 / chunk=FFFFFFFF ⇒ 即时超上限，无假收完无滞留 |
| 3 平方成本（raw_peer.mbt:112-123） | FrameScanner 喂进式增量推进，每字节处理一次，raw 仅一次终态 to_bytes | `sc003_sc004_test`：t8 ≤ 5×t2 且 t8 ≤ 2s |
| 4 只取首个同名头（frames.mbt:172-191） | 头解析收集全部 CL，≥2 即 Broken（TE 分派前） | `frames_scan_wbtest` + `raw_peer_test`：双 CL 同值/异值 ⇒ 畸形可辨认、字节全留存 |
| 5 硬编码 POST /（core/wire_form_test.mbt:129-142） | `RequestLineExpect{method,target}` 参数化辅助 | `sc003_sc004_test`：GET/PUT/带查询路径三形态同辅助全过 |

判定确定性保证（缺陷 1/3 交叉项）：`feed` 为 (state, 字节)→state 纯推进，
同流任意切分同状态转移序列；SC-004 以 ≥5 相位矩阵（白盒直驱）+ 真实 socket
端到端双重钉死。

## 验收口径（收口六门 + 专项）

### 收口六门（quickstart.md §1 有完整命令）

1. `moon check --target native --deny-warn`
2. `moon check --target wasm --deny-warn`
3. `moon test --target native --deny-warn`
4. `moon test --target wasm --deny-warn`
5. `moon fmt --check`
6. `moon info` 后审 `.mbti` diff（core 等公开包期望零 diff；缓存命中不算
   重跑，最终收口轮先 `moon clean`）

### FR-015 观测清单（B-10）

元测试 `fr015_observation_test.mbt` 实测产出，native 与 wasm/moonrun 各一份
（quickstart §3 命令）；断言仅「结局 ∈ {ReaderClosed, OSError}」（E5），
真实结局 println 打点；矩阵 = target × 在途未读数据{有,无}；清单如实注明
依 OS 与在途未读数据而变。**禁止手写断言代替实测**。行为落点：B-10 已按
D2 为「accept 后 close」，RST 能力缺口挂上游欠账（后续单独工单）。

### SC-003/SC-004 执行设计

SC-003 用 `@async.now()` 实测（根包 mbti:26），断言 t8 ≤ 5×t2 且 t8 ≤ 2s，
**常驻默认套**——修复后测试自缚上界（≤2s），不拖慢门禁，故不引入跳过
标记（`--include-skipped` 机制存在但上游无使用先例、语法未核证，YAGNI；
若实测确需收窄，用测试名 glob 按需运行——`-f` 语义为按测试名过滤，
2026-10-18 实测定谳，见 tasks Notes／quickstart §2）。
SC-004 白盒相位矩阵 {1,7,100,8191,8192,8193} 字节切分（含劈中大小行）+
黑盒端到端各一轮。wasm 上 t8 超 2s 的处置顺序：先查算法回归，确因 moonrun
宿主吞吐则走 spec 变更流程附数据修订判据（风险表 R1）。

## 行为清单 ↔ 元测试映射表（包级 DoD-2 对账面，B-01～B-15）

| 行为 | 元测试（文件·盒型） | 状态 |
| --- | --- | --- |
| B-01 延迟响应头 | scripted_server_test·黑盒（`@async.now()` 断头时延） | 计划 |
| B-02 滴流（间隔/块数可调） | scripted_server_test·黑盒（断块到达间隔） | 计划 |
| B-03 重定向链（301/302/303/307/308 + 相对/绝对/畸形 Location） | scripted_server_test·黑盒（US-1 场景 2 逐跳断言） | 计划 |
| B-04 echo 唯一 id（FR-013） | scripted_server_test·黑盒（并发 N，id↔体一一对应） | 计划 |
| B-05 定长/chunked 可选 | scripted_server_test·黑盒（线上字节断帧形态） | 计划 |
| B-06 Connection: close 头 | scripted_server_test·黑盒 | 计划 |
| **B-07 gzip** | — | **M1 缺口·推迟（裁决 D4），不建模不实现** |
| B-08 401/407 挑战（M2 备用） | scripted_server_test·黑盒（可编排+自证） | 计划 |
| B-09 accept 后立即 close | scripted_peer_test·黑盒（US-2 场景 1） | 计划 |
| B-10 关闭形态观测清单（原 RST，D2） | fr015_observation_test·黑盒（双 target 各一份） | 计划 |
| B-11 半截响应头（截断点参数化，判据=钉死错误集合） | scripted_peer_test·黑盒（US-2 场景 2；{BadRequest, ReaderClosed}） | 计划 |
| B-12 慢速接收滴流 | scripted_peer_test·黑盒 | 计划 |
| B-13 原始字节捕获（判定内核重写） | raw_peer_test·黑盒（①–⑦ 既有）+ frames_scan_wbtest·白盒 | 计划（底座已有，本包回归） |
| B-14 随机端口分配/冲突重试 | raw_peer_test ①（既有）+ scripted_server_test（port()>0）；重试分支＝防御性，处置见 T004 | 计划 |
| B-15 生命周期/超时保护 | 各 test 文件的 timeout_ms 路径（如 raw_peer_test ⑥）+ close 幂等用例 | 计划 |

US-3/US-4 判据分别由 B-13（P02 T009 判据源）与 B-02/B-12（P08 预验证）承载，
对应场景在上述元测试中覆盖（spec 测试方案口径）。

## 收尾事项

1. 六门全绿 + `.mbti` diff 审视结论归档（宪法开发工作流）。
2. **回勾 T009**：`specs/002-m1-p02-request-response/tasks.md:207-237`
   （owner 2026-10-16 裁决：T009 保持未勾、等 P03 整包交付；引用位置：
   002 tasks.md T009 条目、本节、quickstart §6）。**owner 2026-10-18 常设
   授权：满足判据即可回勾、无需再次请示**——三条同时成立：① T026 六门
   全绿（含 `moon clean` 后全量重跑）；② 包级 DoD 全通过（含「B-01～B-15 ↔
   任务 ↔ 元测试」映射表对账，B-07 按缺口显式标注口径满足）；③ FR/SC 覆盖
   核对表无缺项。**反例约束**：仅「002 T009 的技术内容已在 P02 交付并通过」
   （2026-10-16 native+wasm 126/126）**不足以**触发回勾——勾与 P03 整包
   交付绑定，两者都要满足；判据不全时不得自主勾选。回勾时在本包留一行
   证据（六门结果 + 对账结论；与 tasks T028 同口径）。
3. spec 002 中 `src/fixtures` 注释性锚点为历史引用，不回改；路径映射
   `src/fixtures → src/internal/fixtures` 以本节与 research.md R1.3 为准。
4. FR-015 两份观测清单随交付归档；RST 上游欠账（后续单独工单写
   docs/roadmap 台账）在交付汇报中列为遗留开口。

## Complexity Tracking

> 无宪法违例，无需豁免记录。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无） | — | — |

## 风险登记（plan 视角最高风险三处）

| # | 风险 | 影响 | 处置 |
| --- | --- | --- | --- |
| R1 | SC-003 的 2s 绝对阈值在 wasm/moonrun 上受宿主吞吐影响，可能因环境而非算法超限 | 唯一可能回改 spec 判据的点 | 先查算法（增量推进有构造性保证）；确因宿主则 spec 变更流程附双 target 数据 |
| R2 | B-11 钉死错误集合 {BadRequest, ReaderClosed} 基于 E4 源码静态推演，真实 `@http.Client` 对三类截断点的实际落点需元测试逐一确认；若现集合外形态需回改 spec | P07 判据面 | 元测试先行穷举三截断点；集合外形态＝spec 变更信号（D3 修正机制已在 spec 标注） |
| R3 | `@http.ServerConnection::write` 有缓冲语义（server.mbt:128-129「MAY be buffered, call flush」），滴流块边界与 chunked 帧形态依赖 flush 保真 | B-02/B-05 元测试写法 | 帧形态断言以线上字节为准（不信任调用序）；flush 粒度问题属夹具内部调整，不动 spec 行为需求 |
