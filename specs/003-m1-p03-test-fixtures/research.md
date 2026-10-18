# Research：P03 可控服务端测试基建（M1-P03）

> 特性：specs/003-m1-p03-test-fixtures ｜ 分支：003-m1-p03-test-fixtures ｜ 日期：2026-10-18
> 规格依据：spec.md（含 2026-10-18 Clarifications D1–D5）；宪法 v1.2.0。
> 本文所有「实测」均给出命令与输出摘录；探针目录已即用即删（src/c1probe、outprobe）。

## R1｜C1 夹具库宿主位置（spec 待澄清项，README.md:117 授权本 plan 裁决）

### R1.1 工具链证据（moon 0.1.20261012，全部实测）

| # | 探针 | 命令 | 结果 |
| --- | --- | --- | --- |
| P-a | 跨模块导入 internal 包 | 建 `src/c1probe/moon.pkg` 导入 `moonbitlang/async/internal/event_loop`，`moon check src/c1probe --target native` | **编译期拒绝**：`Cannot import internal package moonbitlang/async/internal/event_loop@0.22.4 in hahh9527/moonhttp/c1probe@0.1.0 due to internal visibility rules` |
| P-b | 同模块导入 internal 子包 | `src/c1probe/internaldep` + `src/c1probe` 导入 `hahh9527/moonhttp/c1probe/internaldep`，`moon check` | 通过（`Finished. moon: ran 3 tasks`） |
| P-c | 同模块**黑盒测试**导入 internal 包 | `src/c1probe/probe_test.mbt`（`_test.mbt`）内 `@internaldep.dep()`，`moon test src/c1probe --target native` | 通过（`Total tests: 1, passed: 1`）——core 黑盒测试消费夹具的关键形态可用 |
| P-d | pkgtype 合法取值 | `src/c1probe2/moon.pkg` 写 `pkgtype(kind: "test")`，`moon check` | **不存在 test 种类**：`unknown variant `test`, expected one of `library`, `executable`, `foreign_library`` |
| P-e | source 之外目录发现性 | 仓库根建 `outprobe/moon.pkg`（`moon.mod` 有 `source = "src"`），`moon run outprobe` | **不进包搜索路径**：`it is not in the path for searching packages, thus it cannot be resolved to any known package` |
| P-f | 发布面携带内容 | 查 `.mooncakes/moonbitlang/async/src/`（registry 0.22.4 解包） | `*_test.mbt` 与 `internal/` **原样随发布携带**（socket/ 下有 addr_test.mbt 等；src/internal/ 完整在列）——发布不做测试文件/内部包剥离 |
| P-g | moon.mod `private` 字段 | `moon publish --help` | 「The optional `private` field … requests restricted access **when true** … Publishing with private visibility **is not supported yet**, so private modules are currently rejected」——模块级全有/全无开关，且尚未支持 |
| P-h | 质量门旗标存在性 | `moon check --help`、`moon fmt --help`、`moon test --help` | `--deny-warn` ✓、`fmt --check` ✓、`moon test -p <pkg> -f <filter> --include-skipped` ✓ |

旁证（上游手法，D8 只参考不搬运）：`moonbitlang/async` 的模块内测试支撑包是
`src/internal/test_util`（含 `expect_error_async`/`assert_raise_async` 等断言辅助，
`#callsite(autofill(loc))` 手法）；其 `test_programs` 式样例目录**不在**发布包内
（P-f 清单无此项）＝放在 src 之外、不参与 `moon test`。

### R1.2 候选方案对比

| 方案 | 判定 | 代价 |
| --- | --- | --- |
| A. 原位保持 `src/fixtures`（公开 library 包） | 备选 | 公开面永久增长：mooncakes 消费者可 import 我们的测试夹具，`.mbti` 即公开承诺；后续收紧仍要走同一次迁移，届时消费方更多、churn 更大 |
| B. 迁 `src/internal/fixtures`（internal 包，toolchain 强制隔离） | **选定** | 一次性迁移：移动 5 个文件、`src/core/moon.pkg` 导入路径改 1 行、spec 002 的 `src/fixtures` 注释性锚点成为历史引用（不回改 002 文档，在本 plan/tasks 注明映射） |
| C. `test_programs` 式样例目录（src 之外） | 排除 | P-e 实测不进包搜索路径，夹具元测试无法被 `moon test` 发现与构建（正是「每行为一个自证元测试」的载体，不可接受） |
| D. `moon.mod` `private` | 排除 | P-g：模块级开关且尚未支持（发布即被拒），无按包粒度 |
| E. 自立 `pkgtype(kind: "test")` | 排除 | P-d：该种类不存在 |

### R1.3 裁决

**选 B：夹具库迁至 `src/internal/fixtures`，包类型保持 `library`。**

- **为什么**：P-a/P-b/P-c 三探针证明 `internal` 是本工具链**唯一真实生效**的
  按包隔离手段，且恰好覆盖本项目全部消费形态（同模块包导入 + 黑盒测试导入）；
  上游 `src/internal/test_util` 同构（手法对齐，D8）；宪法 VI 简洁——零新抽象，
  仅路径变更；0.x 实验期允许破坏性移动（宪法「实验阶段不保证对外 API 兼容」），
  此刻是 churn 最小的时点（现消费方仅 `src/core/moon.pkg` 1 行）。
- **另一条（A）的代价**：见上表——公开面承诺 + 更晚的收紧成本。
- **公开面承诺与收紧路径说明**（按 owner 要求写明）：迁移后 `internal/fixtures`
  的 `.mbti` **不是对外承诺**（外部模块 import 即编译失败），包级 DoD-3 的
  `moon info` 审视义务保留但泄漏风险面清零；本裁决即「收紧后的终态」，后续
  无需再收紧。若未来确需对外提供夹具（无此需求信号），再走 spec 变更流程
  显式升格为公开包。

## R2｜第 1 类脚本化 HTTP 服务端（B-01～B-06、B-08；B-07 已裁 M1 缺口）

- **Decision**：基于 `@http.Server` 公开 API 自建（mbti:141-171 取证：
  `Server::Server(Addr, dual_stack?/reuse_addr?/headers?)`、`accept`、
  `ServerConnection::send_response(code, reason, extra_headers?)/write/flush/
  end_response/read_request`）。路由声明式：`mount(method, path, ResponseScript)`
  一次声明一个路由的完整响应编排；不接受测试内手写 accept/响应循环（FR-012）。
- **Rationale**：
  - 响应帧形态有公开契约（server.mbt:190-197）：`extra_headers` 带
    `Content-Length: n` → 定长帧（长短不符 raise）；不带 → 逐块写 + `flush`
    保块边界 → chunked 帧。B-05 据此二选一，帧形态由元测试按线上字节断言。
  - `Request` 为 `pub(all) struct { meth, path, headers }`（mbti:110-114），
    路由匹配取 `meth`+`path`，无需侵入。
  - 慢速滴流：`send_response` 后按块 `write` + `@async.sleep(interval)` +
    `end_response`；头延迟：accept 后 `sleep(head_delay_ms)` 再 `send_response`。
    客户端侧观测量（头时延、块间隔）由元测试用 `@async.now()`（根包
    mbti:26，`pub fn now() -> Int64`）度量。
  - echo（FR-013）：响应体 = `<单调自增 id>:<请求体原样>`，id 由夹具每请求分配；
    并发 N 请求下「id ↔ 请求体」一一对应即串号检测判据。
  - 连接模型：自管 accept 循环（不用 `run_forever`，其 `max_connections`/
    `allow_failure` 语义不提供本包所需的每操作超时保护口径）；每连接读一个
    请求、按脚本应答、按脚本决定是否关闭。多连接并发由测试侧 task group 驱动。
- **Alternatives considered**：`run_forever` 托管循环（放弃：超时保护与优雅
  关闭口径不可控，FR-004/FR-012 不满足）；过程式每测试手写服务端（宪法 VI
  与 FR-012 双重排除）。

## R3｜第 2 类裸 TCP 脚本对端（B-09/B-10/B-11/B-12/B-13）

- **Decision**：在既有 `RawPeer` 底座上扩展为程序化对端：
  `PeerProgram = AcceptClose | CloseObservation | PartialResponse(CutPoint) |
  SlowReceive | Capture`，一个句柄按声明的程序服务一次连接（与现
  「一次 start 服务一条请求一次断言」口径一致）。
- **Rationale**：
  - B-09/B-10 合并为 `accept → close` 一种注入（D2 裁决：RST 不可交付）；
    B-10 的交付物是**观测清单**（见 R7）而非行为承诺。
  - B-11 截断点参数化：`CutPoint = Nothing | MidStatusLine(n) | AfterStatusLine
    | MidHeaderLine(n)`，n 为发送的字节数（US-2 场景 2 的 15 字节即
    `MidStatusLine(15)`）；canned 响应字节串来自上游写出形态取证
    （frames.mbt 文件头既有锚点）。
  - B-12 慢速接收：accept 后按声明节奏 `read`（不读满），用于 P08 写侧超时
    场景；实现仅是读循环 + `@async.sleep`。
  - B-13 捕获：语义与公开面不变（`CapturedRequest` 五字段 + note），仅判定
    内核按 R4 重写。
- **Alternatives considered**：为 RST 写本项目自有 C 绑定（`setsockopt(
  SO_LINGER)`/`shutdown()`）——**明确否决**：等于给上游缺口私自补能力、仅
  native 可用、破坏宪法 I 非侵入原则；如确要做，属「需人工批准的候选方案」，
  本 plan 不纳入实施路径（见 plan 宪法符合性一节）。

## R4｜五处继承缺陷的修复手法（FR-006～FR-010，逐条可判定）

### R4.1 缺陷 1＋3（相位无关 × 平方成本）：重写为增量推进的帧扫描状态机

- **Decision**：废弃「每收到 8KiB 对全量已捕获字节 `to_bytes()` 重扫」的
  `scan_frame(raw.to_bytes())` 模式（raw_peer.mbt:112-123），改为
  `FrameScanner::feed(bytes) -> Signal` 增量状态机：
  - 头部态：CRLFCRLF 增量查找，只带 3 字节跨块重叠，头字节计数受
    `max_head_bytes` 约束；
  - chunked 态：大小行以**行缓冲**累积（上限为新设的 `max_size_line_bytes`，
    即大小行**自身长度**上界——不再用流内绝对偏移充当上界，这是 FR-006 的
    判定性修正点）；数据态按剩余计数消费；trailer 态找 CRLFCRLF；
  - 每字节恰好被处理一次（摊还 O(1)），`raw` 仍只做一次性累加
    （FR-005 原样留存不变），捕获结束时一次 `to_bytes()`。
- **为什么判定仍与读取分片无关**：`feed` 是 `(state, 输入字节) → state` 的
  纯推进——同一字节序列的任意切分走同一状态转移序列（大小行跨块时暂存于
  行缓冲，与切分相位无关）。证明方式＝SC-004 元测试：同一 >64KiB chunked
  字节流按 ≥5 种切分相位驱动扫描器（白盒直驱）+ 真实 socket 端到端各一轮，
  断言判定与字节完全一致；辅以白盒单测直接构造「大小行被切在中间」的用例。
- **元测试**：`frames_scan_wbtest.mbt`（白盒，相位矩阵/切分相位穷举小集）+
  `sc003_sc004_test.mbt`（黑盒端到端）。

### R4.2 缺陷 2（数值溢出三型症状）：封顶累加、超限即断

- **Decision**：十进制（Content-Length）与十六进制（chunk 大小）解析改为
  **带封顶的累加**：累加中一旦值超过 `max_body_bytes` 立即
  `Broken("超出夹具上限")` 并停止推进。`max_body_bytes`(16MiB) ≪ 2^31，
  封顶后不可能发生 Int32 回绕——负回绕空负载假收完与滞留到外层超时两型
  症状在构造上不可能，三型归一为「即时如实超上限」一型（FR-007）。
- **元测试**：`Content-Length: 99999999999` → 即时 Broken 超上限（耗时 ≪
  外层超时）；chunk 大小行 `FFFFFFFF` → 同；`800000`(hex, 8MiB) 边界值按
  新上限校准后的行为断言。

### R4.3 缺陷 4（重复 Content-Length）：头部解析改为收集全部同名行

- **Decision**：头部解析不再「只取首个同名行」：收集全部
  `content-length` 出现次数，≥2 即 `Broken("重复 Content-Length")`——
  与 TE 是否在场无关（严格口径，防走私向量），在 TE 分派之前判定。
  单 CL + TE:chunked 时 TE 优先的既有语义不变。
- **元测试**：双 CL（同值/异值两组）→ complete=false、note 可辨认、
  raw/head 全留存（FR-008）。

### R4.4 缺陷 5（断言辅助硬编码 POST /）：方法与路径参数化

- **Decision**：夹具库公开断言辅助 `RequestLineExpect { method, target }` +
  `CapturedRequest::assert_matches(expect, tag)`：断言「帧收完 + 请求行前缀
  等于 `\{method} \{target} HTTP/1.1`」；`src/core/wire_form_test.mbt` 的
  `assert_captured_frame`（:129-142）改为调用该辅助并显式传入期望形态。
  手法参考上游 `expect_error_async` 的 `#callsite(autofill(loc))`
  （仅参考，代码自建，D8）。
- **元测试**：GET /、PUT /x、POST /p?a=b 三种形态经同一辅助全部判定通过
  （FR-009）；失败路径不做断言辅助的自反测试（YAGNI，宪法 VI）。

### R4.5 上限校准（显式决策）

| 常量 | 旧值 | 新值 | 理由 |
| --- | --- | --- | --- |
| `max_head_bytes` | 64KiB | **64KiB（不变）** | 无场景需要更大头部；测试夹具上限非客户端特性 |
| `max_body_bytes` | 8MiB | **16MiB** | SC-003 需 8MB 级捕获并留余量；贴边测试脆弱；仍远小于 2^31，封顶累加安全 |
| `max_size_line_bytes` | （无，误用绝对偏移） | **1KiB（新增）** | 大小行自身长度的真上界（RFC 9112 允许 chunk-ext，1KiB 对测试足够宽）；FR-006 判定支点 |

## R5｜SC-003/SC-004 的可执行自证与测试预算

- **Decision**：
  - **SC-004（确定性）**：白盒相位矩阵（>64KiB chunked 流 × 切分粒度
    {1, 7, 100, 8191, 8192, 8193} 字节，含劈中大小行的相位）断言判定/负载/
    原始字节全同；黑盒端到端再以真实 socket 不同写片重放一轮。常驻默认
    测试套（毫秒级）。
  - **SC-003（性能）**：用 `@async.now()` 实测 2MB 与 8MB chunked 捕获，
    断言 `t8 ≤ 5×t2` 且 `t8 ≤ 2s`。**纳入默认套**：修复后该测试自缚上界
    （断言本身 ≤2s，预期实测数百毫秒），不会拖慢全套——不采用跳过标记
    （`--include-skipped` 机制存在但上游无 `#ignore` 使用先例，语法未在本
    版本核证，YAGNI）。若 wasm 实测超 2s：这是真失败信号（moonrun 吞吐或
    算法回归），处置顺序＝先查算法、确因宿主吞吐则走 spec 变更流程附数据
    修订判据（记入风险）。
- **Rationale**：SC-003 兼任 FR-010 回归门；双 target 各跑一轮，门内成本
  有界（≤2s×2MB+8MB×2 target ≈ 增量数秒）。

## R6｜FR-015 观测清单（B-10）的产出方式

- **Decision**：`fr015_observation_test.mbt` 生成观测清单，**禁止手写断言
  代替实测**：矩阵 = target∈{native, wasm/moonrun} × 关闭前在途未读数据
  ∈{无, 有}，每行跑一次「accept → (按前置条件写 0/N 字节) → close」，
  客户端以裸 socket 读并分类结局。断言口径仅「结局 ∈ {@io.ReaderClosed,
  @os_error.OSError}」（E5：FIN→ReaderClosed；reset→OSError，context 形如
  `@socket.Tcp::read()`，Windows errno 10054）；实际结局用
  `println("[FR-015 观测] target=… pending=… outcome=…")` 打点，native 与
  wasm 各运行一次即得两份清单。清单须如实注明：结局依 OS 与在途未读数据
  而变，不构成行为承诺（D2）。
- **Rationale**：钉死的是「可观测集合」而非单一结局；把不确定性本身记入
  清单正是 spec D2 的要求。

## R7｜元测试组织与双跑口径

- **Decision**：全部元测试收在 `src/internal/fixtures` 包内（自证即本包
  测试，spec 测试方案口径）：

| 文件 | 盒型 | 覆盖 |
| --- | --- | --- |
| `raw_peer_test.mbt`（既有 ①–⑦ 保留） | 黑盒 | B-13 既有自证 + 缺陷回归的端到端锚点 |
| `frames_scan_wbtest.mbt`（新） | 白盒 | FR-006/007/008 单元级（相位矩阵、溢出、双 CL） |
| `scripted_server_test.mbt`（新） | 黑盒 | US-1 三场景 + B-05 帧形态 + B-06 + B-08 |
| `scripted_peer_test.mbt`（新） | 黑盒 | US-2（B-09/B-11/B-12） |
| `fr015_observation_test.mbt`（新） | 黑盒 | B-10 观测清单生成 |
| `sc003_sc004_test.mbt`（新） | 黑盒+白盒 | SC-003/SC-004、FR-009 断言辅助三形态 |

  命名沿用既有 `P03①…` 风格扩为 `P03-Bxxⓝ 描述`；断言优先
  `assert_eq`/`assert_true`（宪法 IV）。双跑＝
  `moon test --target native --deny-warn` 与
  `moon test --target wasm --deny-warn`（fixtures 全部用公开 API，无
  native-stub，wasm 由 moonrun/WASI 宿主承载——既有底座已双绿实证）。
- **core 侧改动**：`wire_form_test.mbt` 换用参数化断言辅助（导入路径随
  R1.3 迁移同步更新）；core 公开面零变化（`.mbti` 零 diff 为收口门之一）。

## R8｜T009 回勾（收口事项）

- **Decision**：P03 整包六门全绿后，回勾
  `specs/002-m1-p02-request-response/tasks.md:207-237` 的 T009
  （owner 2026-10-16 裁决：T009 保持未勾、等 P03 整包交付）。该步骤列入
  plan 收尾清单与后续 tasks 的最后一项；002 文档其余内容不动。
