# M1 性能核心——工作包拆分（roadmap）

> 来源：`proj-init-docs/okhttp-on-async-http/README.md` 里程碑 M1。
> 本目录把 M1 拆为 **10 个工作包（P01–P10）**，每个工作包可单独走一遍
> Spec Kit 最小闭环（`specify → clarify → plan → tasks → implement`），
> 并拥有独立、可判定的验收判据。本 README 只做总览与差异登记；
> 各包细节见同目录 `Pxx-*.md`。
> 拆分不修改 `proj-init-docs`（原报告保持原样，以本 README 的差异清单为准执行）。

## 1. M1 目标与交付判据（沿用原报告口径）

- **范围**：01 请求/响应模型（core）+ 03 连接池核心 + 02 重定向与重试
  + 10 超时与调度 + 性能杠杆 L2（定长帧）/L3（重放零折叠）。
- **交付判据**：
  1. round2 基准复刻：池化路径相对每请求新建连接 **≥20×**（round2 实测 47–56×，门槛留余量）；
  2. stale-retry 闭环：陈旧连接首读失败 → 毒化 → 新连接重放 → 响应正确；
  3. 可控服务端测试全绿（全部网络行为测试基于本地可控服务端，宪法 IV）。
- **人力口径**：原报告 ~16 人日；本拆分逐包加总 ≈ **17 人日**（03 取原 5–7 人日区间下沿），
  差额来自 P03 测试基建单列（原报告将夹具成本摊在各特性测试里）。

## 2. 工作包清单

| 包 | 名称 | 一句话范围 | 前置依赖 | 人力 | 主要来源 |
| --- | --- | --- | --- | --- | --- |
| [P01](P01-core-value-types.md) | core 值对象 | HttpUrl 解析/规范化/resolve + HeadersV 有序多头 | 无 | ~2.75d | 01 §3.2/§3.4 |
| [P02](P02-request-response-bodies.md) | 请求/响应/体模型 | Request/Response/RequestBody/ResponseBody + 定长帧（L2） | P01, P03 | ~1.5d | 01 §3.3/§3.6、14 §2 L2 |
| [P03](P03-test-server-fixtures.md) | 可控服务端测试基建 | 可编程本地服务端/裸 TCP 对端夹具库 | 无 | ~1d | 各篇 §8 汇总 |
| [P04](P04-connection-pool.md) | 连接池 | Address/Lease/LIFO 归还/驱逐/毒化（L1） | P01, P03 | ~3d | 03 §3.1–§3.4 |
| [P05](P05-call-engine-cancel.md) | Call 执行骨架与取消 | execute 直连管线、cancel 三通道、重放零折叠（L3） | P01, P02, P04 | ~1.5d | 01 §3.5/§6 |
| [P06](P06-redirects.md) | 自动重定向 | follow-up 循环、3xx 决策表、priorResponse 链 | P05 | ~1.5d | 02 §3.1/§3.2 |
| [P07](P07-stale-retry.md) | 连接失败重试 | stale-retry 判定、阶段化发送、毒化计数 | P04, P05, P06 | ~1.5d | 02 §3.3 |
| [P08](P08-timeouts-builder.md) | 四类超时与 per-call 配置 | connect/write/read/call 超时接线 + builder 派生 | P05, P06 | ~2d | 10 §3.1/§3.2/§3.4 |
| [P09](P09-dispatcher.md) | Dispatcher 与 enqueue | 双闸并发上限 + FIFO 公平出队 + 可取消 enqueue | P05 | ~1.5d | 10 §3.3、01 §3.5(enqueue) |
| [P10](P10-benchmark-gate.md) | 基准套件与 M1 门禁 | 场景矩阵、三臂对比、≥20× 门禁与基线归档 | P04–P07 | ~1d | 14 §5、03 §8 |

依赖关系（`X → Y` 表示 Y 依赖 X）：

- P01（core 值对象）→ P02、P04（并传递至全部下游）
- P03（测试基建）→ P02、P04（并传递至全部含网络行为的包）
- P02（请求/响应/体）→ P05
- P04（连接池）→ P05、P10
- P05（执行骨架与取消）→ P06、P07、P08、P09
- P06（重定向）→ P07、P08、P10
- P07（stale-retry）→ P10

拓扑分层示意（同层可并行）：

```
层 0（可并行）  P01 core 值对象   P03 测试基建
层 1            P02 请求/响应/体   P04 连接池
层 2            P05 Call 执行骨架与取消
层 3            P06 重定向        P09 Dispatcher
层 4            P07 stale-retry   P08 超时与 builder
层 5（收口）    P10 基准套件与 M1 门禁
```

（P08 硬依赖为 P05、P06，置于 P07 之后是为覆盖「超时×重试」交互场景；P10 依赖
P04–P07，P08/P09 建议先行以纳入其路径。）

建议实施顺序（`→` 串行，`|` 可并行）：

```
P01 | P03 → P02 → P04 → P05 → P06 → P07 → P08 → P10
                                  └→ P09 ────────┘（P09 在 P05 后任意时点插入，P10 前完成）
```

## 3. 与原设计的差异清单（执行以本清单为准）

拆分与裁剪过程中产生的、与 `proj-init-docs/okhttp-on-async-http` 原文的差异，
逐条登记如下（原文不回改）。其中牵扯后续里程碑的条目另提取为跨里程碑跟踪：
总入口 [`../deferred-items.md`](../deferred-items.md)，M1 明细
[`../deferred-items/deferred-items-m1.md`](../deferred-items/deferred-items-m1.md)
（F1–F17，M2–M5 拆分必读）：

| # | 差异 | 原文出处 | 理由与处理 |
| --- | --- | --- | --- |
| D1 | **拦截器链不在 M1 交付**：P05 交付内部执行管线（acquire→发送→收头→归还），预留 exchange 接缝；双层拦截器 API 随 M2（04）插入 | 01 §3.5「execute 经拦截器链（见 04）」；04 属 M2 | M1 判据不涉及拦截器；接缝保证 M2 无重写成本 |
| D2 | **enqueue 与 Dispatcher 合并交付**：`Call::enqueue`/`HttpClient::enqueue` 归 P09（闸门在链首，天然一体）；P05 只交付 execute + cancel | 01 §3.5 将 enqueue 列为 Call API；10 §3.3 | 避免 P05 交付一个无并发控制的 enqueue 再返工 |
| D3 | **代理与 DNS 缓存划出 M1**：M1 的 Address 仅直连三元组（scheme/host/port）；`proxy`/`trust` 指纹字段、代理连接池（03 §3.6）、DNS 缓存（03 §3.5 = L4/I2）归 M2 | 03 §3.1/§3.5/§3.6 | M1≈16d 的算术只容纳池核心+驱逐+毒化；M2 明确含「上游 PR 包（I1/I2）」 |
| D4 | **L3 收敛为「缓存折叠后的头 Map」**：非侵入边界内，重放零成本只能做到 HeadersV→@http Map 每 call 折叠一次、重放复用同一 Map 实例；@http 内部 `send_headers` 的 Map 迭代与逐段 blit 无法从上层消除（消除属侵入项 I8） | 01 §6「拼成 Bytes 缓存」；14 §2 L3 | `Client::request` 公开 API 只收 Map；Bytes 级预序列化需改上游发送路径，违反宪法 I 的非侵入前提 |
| D5 | **RequestBody 仅 Bytes/Stream 两形态**：`File(path, len)` 形态（重开文件重放）随 M2（09，fs stat 待验证）交付 | 01 §3.3 BodySource 三形态 | 09 整篇属 M2；M1 无调用方 |
| D6 | **ResponseBody 便捷方法裁剪**：M1 交付 `bytes()`/`text()`；`json()`（需引 @json 依赖）与 `char_stream` 随 M2 交付 | 01 §3.6 | 依赖面最小化（宪法 VI YAGNI）；char_stream 原文已标 M2 |
| D7 | **重试决策表裁剪**：401/407 行（Authenticator，08 属 M2）与 408 可选项不属 M1，M1 一律终态返回；304 在 M1 语义为「不跟随、直接返回」（缓存层 M4 才存在） | 02 §3.2 决策表 | M2/M4 接入后回补对应行；spec 中显式记录 |
| D8 | **测试与基准夹具自建**：原报告引用的上游仓库资产（`test_programs` cancellation 基建、`examples/http_server_benchmark`、`mio/_connmeasure` Python 夹具）不搬运，P03 自建等价物 | 03 §8、14 §5 | 宪法 I 禁止复制/vendor 上游源码；方法论对齐 round1–3，目标值以其报告数字为参考 |
| D9 | **target 执行口径**（2026-10-14 按宪法 v1.2.0 更新）：M1 不建 wasm-gc stub 与 js 适配层（16 属 M5）；验证面为 native+wasm（check 零错误零警告 + 测试双绿），js/wasm-gc 依宪法 v1.2.0 原则 V（:67-77）标注「暂不验证」并挂欠账（F9），M5 收口时恢复 js 门禁（:130-133） | 16-target-support 属 M5 | 里程碑边界；宪法 v1.2.0 target 条款为口径依据，矩阵标注仍在每包落实 |
| D10 | **故障注入能力口径**（2026-10-18）：原可行性报告 02 §8「服务端 accept 后立即 RST（或 close 不回包）」的手法在本项目不可照做——上游 moonbitlang/async 公开 API 无 shutdown/SO_LINGER（src/socket 全目录无 shutdown，Tcp 只有幂等全双工 close），只能交付 accept 后 close/FIN 与依实测钉死的 FIN/RST 观测清单；RST 属上游能力缺口（欠账 F16，**需人工批准的上游 PR 候选**） | 02 §8（P07 来源） | P03 已按 `specs/003-m1-p03-test-fixtures/spec.md` 澄清 D2 交付（B-10＝close 注入 + 观测清单，FR-015）；P07 相关判据已按 F17 同步改写（见 P07 文档：钉死集合 {BadRequest, ReaderClosed}） |

补充口径说明（非差异，仅为落地澄清）：

- 「10 超时」按原报告特性目录 folder 10 全量理解（含 Dispatcher 与 builder 派生），
  依据 M1≈16d 算术（4.5 + 5 + 3 + 3.5 ≈ 16）。
- **响应头顺序不可保真**（01 §2 已载明的客观约束，验收注意）：@http 响应侧头为无序
  Map 且同名逗号合并，moonhttp 重建 HeadersV 的顺序是遍历序而非线上序；P02 的验收
  场景不得断言响应头线上顺序。保真需侵入解析层（I6/I8），不在 M1。
- 取消语义按宪法 III：以显式 `CallCancelled` 错误变体区分（01 §3.5 原文一致），
  与 OkHttp `IOException("canceled")` 消息判别的映射在 P05 spec 显式记录。

## 4. 每包如何走 speckit

1. 以 `Pxx-*.md` 的「功能描述（speckit 输入种子）」作为 `/speckit-specify` 的特性描述
   输入（可整段粘贴，或指明文件路径让 specify 读取全文）。
2. `clarify` 优先消化该包「澄清问题种子」小节，答案回写 spec。
3. `plan` 必须对照宪法（`.specify/memory/constitution.md`）自查，尤其：非侵入（原则 I）、
   性能数据要求（II，涉性能的包）、测试先行与可控服务端（IV）、target 矩阵（V）、
   `.mbti` diff 审视（VI）、中文（VII）。
4. 建议特性 slug（分支/规格目录名）：`m1-p01-core-value-types`、`m1-p02-request-response`、
   `m1-p03-test-fixtures`、`m1-p04-connection-pool`、`m1-p05-call-engine`、
   `m1-p06-redirects`、`m1-p07-stale-retry`、`m1-p08-timeouts`、
   `m1-p09-dispatcher`、`m1-p10-benchmark-gate`。
5. 包间衔接：下游包的 spec 应引用上游包已冻结的 `.mbti` 接口；上游接口变更时，
  下游未开工的包只需改 roadmap 引用，已开工的包走 spec 变更流程。

## 5. 前置条件（首个包动工前的一次性事项）

- `moon.mod` 增加依赖 `moonbitlang/async`（registry 版本，钉 0.22.x，宪法「技术约束」）。
- 确定包布局映射：core 值对象（P01/P02）入 core 包，执行管线/池/超时/Dispatcher
  （P04–P09）入门面包（现有 `src/client` 骨架可作门面包起点，具体在 P01 的 plan 中定）。
- 测试夹具的宿主位置（独立测试支撑包或 `test_programs` 式样例目录）在 P03 的 plan 中定。

## 6. M1 完成的整体判定

P01–P10 全部包级验收判据通过，且 P10 输出的基准报告满足第 1 节三条交付判据
（≥20×、stale-retry 闭环、可控服务端全绿），宪法质量门（v1.2.0：native/wasm
双绿、`moon info && moon fmt` 干净、`.mbti` diff 已审视、性能数据归档；
js/wasm-gc 暂不验证）逐项核对通过。
