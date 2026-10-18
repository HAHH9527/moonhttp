# Feature Specification: 可控服务端测试基建（M1-P03）

**Feature Branch**: `003-m1-p03-test-fixtures`（分支已存在并在使用，特性目录与分支同名）

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "docs/roadmap/M1/P03-test-server-fixtures.md"（M1 工作包 P03 的 speckit 输入种子全文）＋五处继承缺陷的回归要求（2026-10-18 源码逐行核实，锚点见「既有底座与继承缺陷」）

## Clarifications

### Session 2026-10-18

（owner 批准自主回写：以下 5 问均基于已核实源码证据直接裁决，未向人提问；
证据锚点汇总见「参考」末条，含本次核证的少量行号修正。）

- Q: `@http.Server` 与 `@socket` 在 js target 上是否可用？ → A: 不可用，已核实——
  上游把 `addr.mbt`/`tcp.mbt`/`udp.mbt` 等实现文件全部锁定 `[native, wasm]`
  （`src/socket/moon.pkg:22-43`），`server.mbt` 同样只锁双端
  （`src/http/moon.pkg:51`），js 侧仅剩 `unimplemented.mbt` 占位
  （`src/socket/unimplemented.mbt:17`、`src/http/unimplemented.mbt:17`），
  `Addr` 基元也只有 native/wasm 两支（`src/socket/addr.mbt:25/37/49`），
  上游 README 未勾选项自认未在 JavaScript 实现其他 IO 原语（`README.md:77`）
  （证据 E1，裁决 D1）。质量门保持 native + wasm 双绿不变；js 侧只承诺
  API 层单测，不承诺任何夹具行为
- Q: 夹具能否提供确定性的 RST（abortive close）故障注入？ → A: 不能，已核实——
  全 `src/socket` 无 shutdown，socket.c 的 setsockopt 无 SO_LINGER，`Tcp`
  公开面只有幂等的全双工 `close`（无方向参数），关闭分支是裸 close，无
  「先 shutdown 再 close」写法可借（证据 E3，裁决 D2）。B-10 从「accept 后
  RST」改为「accept 后 close」，本包非目标显式排除「承诺构造 RST」；RST
  能力缺口作为上游欠账（后续单独工单写 docs/roadmap 台账）。夹具 MUST
  如实声明注入形态，并用元测试把「close 实际表现为 FIN 还是 RST」钉成
  可判定的观测清单（native 与 wasm/moonrun 各一份），承认该观测依 OS 与
  在途未读数据而变；不得把 RST 写成可稳定断言的交付行为
- Q: 客户端侧能否区分半截响应头的具体截断点？ → A: 不能，已核实——
  `read_until` 在分隔符未找到但缓冲非空时返回 `Some(残余串)`
  （`src/io/reader.mbt:217-224`），故「缺 CRLF 的半截状态行」也能通过
  `parser.mbt:401-403` 的 guard，错误下移：片段无空格/状态码非数字 →
  `BadRequest`（`parser.mbt:404`），片段形似合法头 → 继续读并在
  `:146/:167/:259` 抛 `ReaderClosed`；`@http` 不暴露「状态行已解析」这类
  部分解析信号（`client.mbt:232-253`）（证据 E4，裁决 D3）。半截响应头
  注入照常交付（截断点参数化），但验收判据改为「夹具侧声明截断点 +
  客户端错误落在钉死的可观测集合 {BadRequest, ReaderClosed} 内」；P07 的
  「不可重试」分支不得以「客户端能观测到状态行已解析」为判据——此为对
  P07 种子的修正（P07 roadmap 对应场景后续单独修订）。2026-10-18 工单 C
  精确化：不可重试分支判据＝`BadRequest` 错误类型本身（协议错误族，对齐
  OkHttp RetryAndFollowUpInterceptor.kt:171-173），`ReaderClosed` 属可重试
  面（EOF 路径，对齐 :197 兜底与 Http1ExchangeCodec.kt:247-252）——钉死
  集合是可观测集合、不等同可重试集合（P03 自身验收判据不变：仍只断言
  可观测集合）
- Q: gzip 响应脚本 M1 是否需要？ → A: 不需要——`@http` 客户端已有
  auto_decompress 透明解压（`src/http/parser.mbt:395/414`），断言需求已
  覆盖；P10 的 gzip on/off 场景按其专用自建服务端处理（裁决 D4）。B-07
  标注「M1 缺口·推迟」，包级 DoD-2 按「缺口显式标注」口径满足
- Q: 夹具库宿主位置由谁裁决？ → A: 维持由 plan 裁决，spec 保持与宿主位置
  正交（裁决 D5，现状确认）

## User Scenarios & Testing *(mandatory)*

<!--
  用户故事按重要性排序；每条故事独立可测——只实现其中一条也应产出可用价值。
  优先级继承种子文件：US-1/US-2/US-3 为 P1，US-4 为 P2；
  US-5 为用户输入显式追加的继承缺陷回归（P1）。
-->

### User Story 1 - 脚本化 HTTP 场景（Priority: P1）

作为 M1 各特性的测试编写者，我启动一个行为可脚本化的本地 HTTP 服务端，
按路由返回可编排的响应（延迟/重定向/echo/连接关闭头；压缩脚本为
M1 缺口·推迟，见澄清 D4）。

**Why this priority**: M1 过半网络行为测试（重定向 P06、超时 P08、池并发 P04）
的公共底座；不先交付它，后续各包的验收场景无从落地。

**Independent Test**: 夹具元测试自证行为编排（证明夹具确实产生预期行为）；
并用 `@http.Client` 原语直连夹具验证行为（种子独立测试口径）。

**Acceptance Scenarios**:

1. **Given** 路由 `GET /slow` 配置「延迟 300ms 后回响应头、body 再滴 3 块、每块间隔
   100ms」，**When** 直连请求，**Then** 观测到响应头时延与 body 到达间隔符合编排。
2. **Given** 重定向脚本 `[301→/a, 302→相对 ../b, 303→绝对 http://127.0.0.1:PORT/c]`，
   **When** 逐跳请求，**Then** 状态码与 Location 逐项符合。
3. **Given** echo 路由，**When** 并发 N 个带唯一 id 的请求，**Then** 每个 body 精确回显
   自身 id（串号检测的判据来源）。

---

### User Story 2 - 裸 TCP 故障注入（Priority: P1）

作为 stale-retry/取消/超时的测试编写者，我用裸 TCP 对端注入网络级故障：
接受后立即断开（模拟陈旧连接被静默关闭）、回半截响应头后断、慢速接收。

**Why this priority**: P07 stale-retry 的「可重试/不可重试」分界判据直接来源于
本类故障注入（判据形态见 FR-012 与澄清 D3：以夹具声明的截断点 + 钉死的
客户端错误集合为准）；P05 取消、P08 超时同样消费。

**Independent Test**: 以裸字节客户端驱动夹具的元测试（同 `src/internal/fixtures`
既有自证手法；`src/fixtures` 为迁移前路径，映射见 plan 收尾事项 3），
断言客户端在每种故障下收到的可观测结果。

**Acceptance Scenarios**:

1. **Given** 「accept 后立即 close」脚本，**When** 客户端在复用连接上发请求，
   **Then** 客户端收到 EOF/ReaderClosed 类错误（为 P07 提供判据）。
2. **Given** 「回 15 字节状态行片段后断」脚本（截断点由夹具声明），**When** 请求，
   **Then** 客户端在读响应头阶段失败，错误落在钉死的可观测集合内
   （{BadRequest, ReaderClosed}，具体形态由声明的截断点映射，证据 E4）；
   不采用「未解析出完整状态行」这类客户端不可观测的判据（对 P07 种子的
   修正，见澄清 D3）。

---

### User Story 3 - 原始字节捕获（Priority: P1）

作为定长帧/头折叠的测试编写者，我用捕获型 TCP 对端拿到客户端发出的
原始请求字节，逐字节断言线上形态。

**Why this priority**: P02 定长帧字节断言（002 tasks 的 T009/SC-002）已经消费该能力；
底座已落地（见「既有底座与继承缺陷」），本包保证其判定语义不腐烂。

**Independent Test**: 手写字节流驱动捕获对端的元测试，比对捕获结果
（head/body/raw 逐字节）与判停标记。

**Acceptance Scenarios**:

1. **Given** 捕获对端，**When** 发送定长 POST，**Then** 捕获字节可解析出
   `Content-Length` 头且不含 `Transfer-Encoding`（P02 US-2 的判据来源）。
2. **Given** 捕获对端，**When** 同一请求重放两次，**Then** 两次捕获字节逐字节相同
   （重放一致性的判据来源）。

---

### User Story 4 - 慢速滴流参数化（Priority: P2）

作为超时特性的测试编写者（P08），我配置「持续但慢速滴数据的 body」，
以验证 read 超时的按操作重置语义。

**Why this priority**: P08 专用场景，依赖 US-1 的滴流编排能力，可后置交付。

**Independent Test**: 以原生 `@http.Client` 预验证滴流节奏的元测试
（种子口径：本夹具用原生客户端预验证）。

**Acceptance Scenarios**:

1. **Given** 每 200ms 滴 1KB、总时长 3s 的 body，**When** read_ms=1000 的按操作超时，
   **Then** 不触发超时（每块间隔 < 超时阈值）——本夹具用原生 `@http.Client` 预验证。

---

### User Story 5 - 大负载与畸形帧的确定性判定（继承缺陷回归，Priority: P1）

作为夹具库的使用者与既有 002 tasks T009 判据的维护者，我要求捕获对端在大负载
chunked 场景与畸形输入下的判定确定、即时、与读取分片相位无关，且断言
辅助不预设请求形态。

**Why this priority**: 五处已核实缺陷（见「既有底座与继承缺陷」）直接威胁
既有线上字节判据的可信度：相位性假 Broken 让大负载场景 flaky、溢出可致
空体假收完、平方成本让 8MB 级流实测不可用（10.2s）、重复头漏检、断言辅助
换请求形态即失效。不回归修复，底座交付即带病。

**Independent Test**: 以构造字节流（多种分片相位、超大数值、重复头、
非 POST 形态）驱动捕获对端的元测试，判定结果二值可断言。

**Acceptance Scenarios**:

1. **Given** 负载超过 64KiB 的 chunked 请求流，且构造使某个 chunk 大小行恰好被
   读取边界劈开，**When** 捕获，**Then** 帧完整收完、重组负载逐字节等于发送内容、
   原始字节逐字节等于线上字节；同一字节流以至少 5 种不同分片相位重放，
   判定结果与捕获字节完全一致。
2. **Given** Content-Length 为 20 位十进制超大值的请求（以及 chunk 大小行为
   超大十六进制值的 chunked 请求），**When** 捕获，**Then** 即时返回可辨认的
   「超出夹具上限」未收完判定且头部区间保留；不得出现空负载假收完，
   不得滞留等待直至外层超时才了结。
3. **Given** 携带两个 Content-Length 头的请求，**When** 捕获，**Then** 判定为畸形
   并给出可辨认的说明，已捕获字节全数留存（不静默取首个同名头继续判定）。
4. **Given** 捕获断言辅助，**When** 以 GET、PUT、带查询串路径三种请求形态驱动，
   **Then** 同一辅助对全部形态给出正确判定（不预设「POST /」前提）。
5. **Given** 8MB 级 chunked 请求流，**When** 捕获，**Then** 在 SC-003 的预算内
   完成且捕获字节逐字节一致。

---

### Edge Cases

- 端口耗尽/夹具端口冲突：自动重试分配（种子边界用例）。
- 夹具停止时有在途连接：优雅关闭语义显式定义并可判定（种子边界用例）。
- 捕获对端收到畸形请求字节：夹具不得 panic，如实留存（种子边界用例）。
- wasm 宿主上 close 的线上形态（FIN/RST）依 OS 与在途未读数据而变：
  以钉死的观测清单如实记录，不承诺构造 RST（FR-015；澄清 D2，证据 E3/E5）。
- 半截响应头的客户端错误形态依片段内容落 BadRequest 或 ReaderClosed：
  以「夹具声明截断点 + 钉死错误集合」为判据（US-2/FR-012；澄清 D3，证据 E4）。
- 读取边界恰好劈在 chunk 大小行中间：判定不得依赖分片相位（FR-006；
  继承缺陷 1 的触发条件）。
- Content-Length / chunk 大小数值超出可表示范围或夹具上限：三型歧义症状
  归一为如实回报（FR-007；继承缺陷 2）。
- 重复 Content-Length 头：检出即判畸形（FR-008；继承缺陷 4）。
- 非「POST /」的请求形态驱动断言辅助：照常可判定（FR-009；继承缺陷 5）。

## Requirements *(mandatory)*

### 既有底座与继承缺陷

**既定事实登记（2026-10-16，P02/T009 先行落地实测）**——本包的既有底座，
作为规格前提登记（非本包新需求，但其判定语义的缺陷回归由本包交付）：

> 第 2 类夹具中的「原始字节捕获」已在 `src/fixtures` 落地（`RawPeer` 捕获
> 对端 + 帧边界判停，基于 `@socket`/`@async` 公开 API，仅连 127.0.0.1，
> 附自证元测试），且 native + wasm 双 target 可跑（wasm 侧由 moonrun/WASI
> 宿主提供平台专用 socket 导入，`moon test --target wasm` 实测全绿、捕获
> 端口逐次不同；口径见 spec 002 A8 方案 c 回写）。第 1 类脚本化 HTTP 服务端
> 与第 2 类其余行为（close/RST、半截响应注入、慢速滴流等）由本包交付。
> 夹具宿主位置是否调整（README:117）由本包 plan 处置（澄清 C1），本登记
> 不代为决定。
>
> 澄清校准（2026-10-18，裁决 D2/D1）：上文「close/RST」中的 RST 不可经公开
> API 确定性构造（证据 E3）——本包交付口径改为 close 注入 + 关闭形态观测
> 清单（FR-015）；「平台专用 socket 导入」实为 wasm 宿主须同时提供 unix 与
> windows 两套导入符号，由运行时按 @event_loop.platform 分派、与宿主 OS
> 无关（证据 E2）。

**继承缺陷登记（2026-10-18 源码逐行核实，本包必须回归，行为要求见
FR-006～FR-010）**：

1. `src/fixtures/frames.mbt:270-275`——chunked 推进把流内绝对偏移 `pos` 误当作
   chunk 大小行自身长度的上界（与 64KiB 头部上限比较）：负载超过 64KiB 的
   chunked 流若读取边界劈在大小行上会假判损坏并提前关连接；是否触发由
   「块长 × 8192 读缓冲」的相位决定，flaky 不可预测。
2. `src/fixtures/frames.mbt:195-217`（十进制）与 `:236-258`（十六进制）——数值
   解析按 32 位有符号整数累加，溢出有三型症状：假判上限损坏 / 等待更多数据
   直至外层超时 / 负回绕致空负载假收完。
3. `src/fixtures/raw_peer.mbt:112-123`——每收到 8KiB 即对全量已捕获字节做整体
   复制重扫，成本随体积平方增长（8MB 流实测约 10.2 秒）。
4. `src/fixtures/frames.mbt:172-191`——头查找只取首个同名行，重复
   Content-Length 检不出。
5. `src/core/wire_form_test.mbt:129-142`——捕获断言辅助硬编码「请求行为
   `POST / HTTP/1.1`」前提，换请求形态即失效。

### 范围

**包含**：

- 夹具库包（位置在 plan 阶段定：独立测试支撑包或样例目录；澄清 C1）。
- 行为脚本清单所列两类夹具的全部行为脚本与驱动辅助。
- 每种行为一个自证用例（夹具的「元测试」：证明夹具确实产生预期行为）。

**非目标（显式排除）**：

- TLS/https 夹具（M3/07 需要时扩展；M1 全部场景 loopback 明文 http）。
- 外部网络依赖、真实互联网地址（宪法 IV）。
- 性能压测服务端的高吞吐优化（P10 基准若需专用服务端，在 P10 内按
  `examples/http_server_benchmark` 手法自建，不与本库耦合）。
- HTTP/2 服务端（M6）。
- 承诺构造 RST（abortive close）：公开 API 无 shutdown、无 SO_LINGER，
  无法确定性构造（证据 E3）；RST 能力缺口作为上游欠账登记（后续单独工单
  写 docs/roadmap 台账），不在本包交付（裁决 D2）。

### 行为脚本清单（范围基线，包级 DoD-2 的对账面）

第 1 类——脚本化 HTTP 服务端（基于 `@http.Server`）：

| 编号 | 行为 | 参数 | 消费方 |
| --- | --- | --- | --- |
| B-01 | 延迟响应头 | 延迟时长可调 | P06/P08 |
| B-02 | 延迟体/慢速滴流 | 块数与滴流间隔可调 | P08（US-4） |
| B-03 | 重定向链 | 跳数任意；状态码 301/302/303/307/308；Location 相对/绝对/畸形 | P06 |
| B-04 | echo 回显 | 每请求唯一 id 注入 body | P04 串号检测 |
| B-05 | 帧形态可选 | 定长/chunked | P02/P04 |
| B-06 | `Connection: close` 头 | — | P07 |
| B-07 | gzip 响应 | **M1 缺口·推迟**（@http 客户端已有 auto_decompress 透明解压，parser.mbt:395/414；P10 gzip on/off 按其专用自建服务端处理；裁决 D4） | P10（不在本包） |
| B-08 | 401/407 挑战 | M2 备用；M1 仅要求行为可编排并可自证 | M2 |

第 2 类——裸 TCP 脚本对端（基于 `@socket`）：

| 编号 | 行为 | 参数 | 消费方 |
| --- | --- | --- | --- |
| B-09 | accept 后立即 close | — | P07 |
| B-10 | accept 后 close（原「accept 后 RST」裁定不可交付：公开 API 无法确定性构造 abortive close，裁决 D2/证据 E3） | 附「close 实际表现为 FIN 还是 RST」的可判定观测清单（native 与 wasm/moonrun 各一份） | P07 |
| B-11 | 半截响应头注入后断 | 截断点参数化：状态行前/状态行后/头行中间；验收判据＝客户端错误落在钉死集合 {BadRequest, ReaderClosed}（证据 E4；集合仅可观测面——不可重试分支判据＝BadRequest 错误类型本身，2026-10-18 工单 C 精确化，P03 验收判据不变） | P07 可重试/不可重试分界（判据修正见裁决 D3） |
| B-12 | 慢速滴流（裸 TCP 形态） | 滴流节奏可调 | P08 |
| B-13 | 原始字节捕获 | 既已落地（既有底座）；本包回归其判定语义（FR-006～FR-010） | P02/P03 |

驱动辅助：

| 编号 | 行为 | 说明 |
| --- | --- | --- |
| B-14 | 随机端口分配 | 绑定保留端口由系统回填实际端口；端口冲突自动重试 |
| B-15 | 夹具生命周期 | 启动/停止/超时保护 |

### Functional Requirements

- **FR-001**（种子）夹具库 MUST 仅依赖 `@http.Server`/`@socket` 公开 API，零侵入；
  禁止 fork、复制或 vendor 上游源码，不搬运上游 `test_programs`/`examples`/`mio`
  测试资产（差异 D8）——手法可对齐，代码自建。
- **FR-002**（种子；B-07 例外见裁决 D4）行为脚本清单（B-01～B-15，B-07 为
  M1 缺口·推迟除外）中每一项 MUST 有至少一个自证元测试
  （夹具的「元测试」：证明夹具确实产生预期行为），元测试通过/失败二值可判定，
  防夹具自身腐烂。
- **FR-003**（种子）全部夹具 MUST 仅监听 loopback（127.0.0.1/::1），任何场景
  不得解析或连接外部主机名/真实互联网地址（宪法 IV）。
- **FR-004**（种子）夹具生命周期 MUST 有超时保护：任一夹具操作（启动/接受连接/
  等待帧/停止）在声明超时后 MUST 返回，挂起的夹具不得拖死测试进程；
  停止时有在途连接 MUST 走显式定义、元测试可判定的优雅关闭语义
  （不再接受新连接；在途连接按声明的语义收尾或按超时截断）。
- **FR-005**（种子）原始字节捕获 MUST 保序、保完整（不聚合丢失、不改动字节）：
  捕获的原始字节与线上字节逐字节一致，畸形与未收完路径下已匹配字节同样全数留存。
- **FR-006**（缺陷 1 回归）chunked 帧判定 MUST 与读取分片相位无关：对负载超过
  64KiB 的 chunked 请求流，无论底层读取如何分片——包括恰好劈在任一 chunk
  大小行中间——MUST 判为完整收完且重组负载正确；同一字节流以不同分片方式
  重复捕获，判定结果与捕获字节 MUST 完全一致。MUST NOT 出现「把流内绝对偏移
  当作大小行自身长度上界而假判损坏并提前关连接」的行为。
- **FR-007**（缺陷 2 回归）数值字段（Content-Length 十进制、chunk 大小行十六进制）
  遇到超出夹具声明上限或不可表示的超大值时，MUST 归一为即时、可辨认的
  「超出夹具上限」未收完判定；MUST NOT 出现负回绕导致的空负载假收完，
  MUST NOT 因数值问题滞留等待直至外层超时才了结。
- **FR-008**（缺陷 4 回归）捕获对端遇到两个及以上 Content-Length 头时
  （无论各值是否相同）MUST 判为畸形并如实回报（未收完 + 可辨认说明），
  MUST NOT 静默取首个同名头继续判定。
- **FR-009**（缺陷 5 回归）捕获断言辅助 MUST 不预设请求方法与路径：请求形态
  （方法、路径、头、体形态）是断言的显式入参；对清单外任意请求形态
  （至少覆盖 GET、PUT、带查询串路径三种）同一辅助 MUST 照常可判定。
- **FR-010**（缺陷 3 回归）捕获对端单次捕获的耗时 MUST 不随已捕获体积平方增长：
  体积翻倍时耗时增幅近似线性（判据见 SC-003），大体量流（8MB 级）MUST 在
  测试预算内完成。
- **FR-011**（种子边界）夹具端口分配 MUST 支持「绑定保留端口 → 系统回填实际
  端口」，端口冲突时 MUST 自动重试分配；实际端口 MUST 可查询且非 0。
- **FR-012**（种子关键设计；验收判据按澄清 D3/证据 E4 修正）脚本化服务端的
  行为编排 MUST 为声明式（行为脚本），测试以一处声明表达一种行为组合
  （延迟参数、状态码与跳数、截断点等），MUST NOT 要求每个测试手写过程式
  服务端循环；「半截响应头」的截断点 MUST 参数化（状态行前/状态行后/
  头行中间），其验收判据为「夹具侧声明截断点 + 客户端错误落在钉死的
  可观测集合 {BadRequest, ReaderClosed} 内」——@http 的错误面不足以区分
  截断点（E4：read_until 对缺 CRLF 的半截状态行仍返回 Some，错误下移），
  因此 P07 的「不可重试」分支不得以「客户端能观测到状态行已解析」为判据
  （对 P07 种子的修正；P07 roadmap 对应场景后续单独修订）。
- **FR-013**（种子关键设计）echo 行为 MUST 为每请求注入唯一 id 并原样回显，
  使响应体与请求一一对应（P04「响应体串号检测」的判据基础）。
- **FR-014**（种子边界）捕获对端收到任意畸形请求字节（非 HTTP 垃圾、坏帧）
  MUST 不 panic、不无限累加，如实回报未收完并全数留存已捕获字节。
- **FR-015**（裁决 D2，替代原「wasm 记录义务」口径）夹具 MUST 如实声明每条
  故障注入的实际形态；对「accept 后 close」类关闭注入，MUST 用元测试把
  「close 在线上实际表现为 FIN 还是 RST」钉成可判定的观测清单（native 与
  wasm/moonrun 各一份），并承认该观测依 OS 与在途未读数据而变
  （证据 E3；客户端侧佐证：reset 表现为 @os_error.OSError、FIN 收尾表现为
  @io.ReaderClosed，证据 E5）。MUST NOT 把 RST 写成可稳定断言的交付行为。
  wasm 宿主侧的事实口径：宿主须同时提供 unix 与 windows 两套导入符号，
  由运行时按 @event_loop.platform 分派、与宿主 OS 无关（证据 E2）。

### Key Entities

- **行为脚本（路由编排项）**：一条路由到一组可编排行为的声明——状态码、延迟
  （头/体）、滴流块数与间隔、重定向跳数与 Location 形态、echo id 注入、帧形态
  （定长/chunked）、连接关闭头、压缩（B-07，M1 缺口·推迟，裁决 D4）、挑战；
  只暴露测试关心的可观测行为。
- **捕获结果（既有 `CapturedRequest` 语义）**：头部区字节、重组负载、全量原始
  字节、块编码标记、帧完整标记、未收完说明；本包扩充其判定语义（相位无关、
  超上限归一、重复头检出）而不改变「原样留存」承诺。
- **夹具句柄（生命周期）**：启动（回填实际监听端口）、按脚本服务请求、
  停止（含在途连接优雅关闭语义）、超时保护参数。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 行为脚本清单 100% 覆盖——B-01～B-15 中除 B-07（M1 缺口·推迟，
  裁决 D4）外的每一项都有对应自证元测试，且在 native 与 wasm 双目标全绿
  （US-1～US-5 的全部验收场景均以元测试表达）。
- **SC-002**: 测试编写者使用清单内既有行为编写一个新的网络行为测试时，
  无需修改夹具库代码（纯声明式编排；零处过程式服务端手写）。
- **SC-003**: 捕获耗时近似线性——分别以 2MB 与 8MB chunked 流驱动捕获，
  8MB 耗时 ≤ 2MB 耗时的 5 倍（平方增长约为 16 倍），且 8MB 单次捕获 ≤ 2 秒
  （对照继承缺陷 3 实测约 10.2 秒）。
- **SC-004**: 判定确定性——同一超过 64KiB 的 chunked 字节流以至少 5 种不同
  分片相位重复捕获，判定结果与捕获字节 100% 一致（0 次 flaky）。
- **SC-005**: 外部网络依赖为 0——全部元测试仅访问 loopback 地址
  （127.0.0.1/::1），断网环境下全套元测试仍可全绿。
- **SC-006**: 夹具无泄漏——连续运行全套元测试后无监听端口残留、无进程悬挂；
  任一夹具操作在最迟超时上限内必返回（由全套元测试总时长稳定在 CI 预算内
  佐证，无挂起案例）。

## Assumptions

- 夹具库宿主位置（澄清 C1：`src` 内测试支撑包 vs 独立样例目录）由
  plan 裁决（2026-10-18 澄清确认维持，裁决 D5）；本 spec 全部行为需求与
  宿主位置正交。
- js 目标已核实不可监听（证据 E1，裁决 D1）：js 侧只承诺 API 层单测，
  不承诺任何夹具行为；本包质量门仍为 native + wasm 双绿。
- RST（abortive close）不可经公开 API 确定性构造（证据 E3，裁决 D2）：
  关闭注入的线上形态以 FR-015 观测清单钉死，承认依 OS 与在途未读数据而变。
- 夹具保护上限沿用既有口径（头部 64KiB、单体 8MiB），plan 阶段可校准；
  超上限行为以 FR-007 为准。
- SC-003 的「8MB ≤ 2 秒」与「5 倍线性」阈值基于继承缺陷 3 的实测
  （约 10.2 秒、平方成本）推算，clarify/plan 可校准，但不允许劣化到平方量级。

## 宪法合规口径（Target 矩阵 / 性能影响 / 测试方案）

**Target 矩阵（宪法 V）**：

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 主战场（质量门双绿 target）；wasm 宿主须同时提供 unix 与 windows 两套 socket 导入符号、与宿主 OS 无关（证据 E2）；close 关闭形态观测清单见 FR-015（裁决 D2） |
| js | ⚠️ | 已核实不可监听（证据 E1：socket/http 实现文件锁定 [native, wasm]，js 仅 unimplemented 占位，Addr 基元亦缺 js 支）；js 只承诺 API 层单测，不承诺任何夹具行为（裁决 D1） |
| wasm-gc | ❌ | 上游 runtime 缺口（README D9） |

**性能影响**：不适用（测试基建，冷路径，宪法 II 的简洁优先区）。
本包不设热路径性能交付物；FR-010/SC-003 仅约束夹具自身的可用性时延
（防继承缺陷 3 的平方成本损害测试体验），不构成性能优化工作项。

**测试方案**：自证元测试即本包测试——US-1～US-5 全部验收场景各以元测试表达；
native + wasm 双绿为合入门禁（宪法 IV/V）。

## 包级 DoD（验收判据）

1. US-1～US-5 元测试全绿（native/wasm 双 target）。
2. 行为脚本清单（本 spec B-01～B-15）与实现一一对应，缺口在 spec 显式标注
   （B-07 为已裁决的「M1 缺口·推迟」，裁决 D4）。
3. `moon info && moon fmt` 干净（若为 src 内包）。

## 待澄清项（2026-10-18 澄清后：C2/C3/C4 已结案，余项移交 plan/欠账）

- **C1**（移交 plan 裁决，裁决 D5）夹具库宿主位置：`src` 内测试支撑包 vs
  独立样例目录（moon 对测试专用包的发布语义）。
- **RST 能力缺口**（上游欠账，裁决 D2）公开 API 无法确定性构造 abortive
  close；后续单独工单写 docs/roadmap 台账，不在本包交付。

（原 C2/C3/C4 已于 2026-10-18 会话结案：C2→D1、C3→D2、C4→D4，
见「Clarifications」。）

## 参考

- `docs/roadmap/M1/P03-test-server-fixtures.md`（本包唯一规格种子）
- `src/fixtures/frames.mbt`、`src/fixtures/raw_peer.mbt`、`src/fixtures/raw_peer_test.mbt`
  （既有底座与继承缺陷 1–4 的行号锚点；迁移前路径，迁移后为
  `src/internal/fixtures`，映射见 plan 收尾事项 3）
- `src/core/wire_form_test.mbt:129-142`（继承缺陷 5 的行号锚点）
- 各特性篇 §8（测试方案对夹具的需求汇总）：`proj-init-docs/okhttp-on-async-http/`
  01 §8、02 §8、03 §8、10 §8
- `03-connection-pool/README.md` §5（wasm 宿主 socket 语义差异提示）
- `specs/002-m1-p02-request-response/spec.md`（A8 方案 c 的 wasm 口径回写）
- `docs/roadmap/M1/README.md`（差异 D8：上游测试资产不搬运；D9：wasm-gc 缺口）
- `.specify/memory/constitution.md`（原则 I/IV/V/VII）
- 上游取证锚点（证据 E1–E5，2026-10-18 会话逐条核证，均在
  `.mooncakes/moonbitlang/async/` 下）：`src/socket/moon.pkg:22-43`、
  `src/http/moon.pkg:51`、`src/socket/unimplemented.mbt:17`、
  `src/http/unimplemented.mbt:17`、`src/socket/addr.mbt:25/37/49`、
  `README.md:77`（E1）；`src/socket/ffi.wasm.mbt:17/184/197/201/219`、
  `src/internal/event_loop/network_unix.mbt:231`、`network_windows.mbt:165`、
  `io_result.wasm.mbt:209/233`、`event_bus.wasm.mbt:98/102`、
  `src/socket/tcp.mbt:238-245`（E2）；`src/socket/socket.c`
  （:84/97/103/110/142/156/167/168/172/173/260/288-307，且全 src/socket
  无 shutdown/LINGER）、`src/socket/pkg.generated.mbti:45-78`、
  `src/internal/event_loop/io.mbt:73-81`（E3）；`src/io/reader.mbt:88-98/217-224`、
  `src/http/parser.mbt:146/167/259/401-404`、`src/http/client.mbt:232-253`（E4）；
  `src/internal/event_loop/io_windows.mbt:136-144`、
  `src/os_error/errno_windows.mbt:15-46`（E5）。
  （核证注：E1 的 README 未勾选项实际在 :77；E3 的 IoHandle::close 与 E5 的
  io_windows/errno_windows 实际位于 `src/internal/event_loop/` 与
  `src/os_error/`——均为锚点小漂移，证据实质全部成立。）
