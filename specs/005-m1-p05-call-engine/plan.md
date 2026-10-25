# Implementation Plan: Call 执行骨架与取消（M1-P05）

**Branch**: `005-m1-p05-call-engine-cancel` | **Date**: 2026-10-24
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from
`/specs/005-m1-p05-call-engine/spec.md`
（含 2026-10-24 Clarifications 两问裁决：C2 维持两段式、C3 最小面；C1/C2
的 plan 核实结果见 research.md R1/R3 并回记 spec）

**Note**: 全部源码级证据与决策（R1–R8）在 research.md，本文引用不重复。

## Summary

交付 moonhttp 的执行管线骨架：`HttpClient` 门面（持 P04 池）+ `Call`
一次性 `execute`（单次 exchange：租借→折叠→发送→收头→构建）+ `cancel`
三通道（标记 / 子任务组 `Task::cancel` 在途取消 / 租约毒化不回池）+
L3 折叠缓存（每 Call 恰一次 `to_http_map`）+ 体生命周期处置闭环
（Consumed→回池；`dispose`→skip 回池或毒化；取消/异常→毒化）。
exchange 接缝（内部 `exchange_once`）为 M2 拦截器链与 P06/P07 循环预留。
C2 裁决触发 FR-015 预留支点：core 增显式异步收尾 API
`ResponseBody::dispose`（client 冻结面零变化）；量化性能验收归 P10，
本包只断言机制正确性（SC-004 计数 + 字节级）。

## Technical Context

**Language/Version**: MoonBit，moon ≥ 0.1.20261012（003 已核证口径）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（registry 钉版，
moon.mod 既有）；仅用 `@async`/`@http` 公开 API（research R1/R2 逐条锚点；
弃用面零引用）；本模块 core 包（P01/P02 已交付）；**零新增外部依赖**

**Storage**: N/A（纯内存编排）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；白盒承载
桩接缝重放/折叠计数/状态机/竞争断言；全部基于 P03 本地夹具；命名
`P05-<域><序> 描述`（R8）

**Target Platform**: native + wasm 双绿为门；js **未验证**（D14/F9：仅
`moon check --target js` + 可行时 node 冒烟，零 `#cfg(js)` 分支）；
wasm-gc 排除

**Project Type**: library（门面包 `src/client` 增量 + core 包 FR-015 裁决面）

**Performance Goals**: L3 重放零折叠为机制级交付（SC-004）；热路径新增
对象 ≈ Lease + Response 壳 + Call 壳（01 §6 口径）；折叠缓存消除重放路径
的重复 Map 构建；「≥20×」量化门禁归 P10，本包不断言延迟数字

**Constraints**: 全程公开 API（宪法 I，R1/R2 锚点清单）；execute 单轮
无 follow-up 循环（FR-006）；1xx 回调不进公开面（C3）；取消收尾仅同步
操作（R1 证据：handle_cancellation→None 后 async 立即取消）；禁 sleep
串联；`src/client/placeholder` 本包不删（P6 延续）

**Scale/Scope**: `src/client` 增 3 文件 + 测试 2 文件；`src/core` 公开
面增 2 处（contracts §2）+ core 测试文件 1 处改动（T003）；FR-001～
FR-015、SC-001～SC-007

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过**：全部设计仅经 `@async`/`@http` 公开 API（R1/R2 锚点表）；不 fork/复制/vendor；上游改动与 issue/PR 零需求。**显式否决①**：绕开 Lease 直取 `@socket.Tcp` 建连——破坏 P04 池契约与单请求在途状态机。**显式否决②**：为 Dropped 路径 fork/patch @http——以 core 显式 API（FR-015 裁决）替代 |
| II 性能优先 | 通过：折叠缓存（FR-004）为机制级性能交付并带计数断言；管线零新增分配放大（Call 壳 + Response 壳）；量化归 P10；取消通道用 O(1) 标记 + Task 句柄，无轮询 |
| III OkHttp 语义对齐 | 通过：Call 一次性/取消判别/无闸门并发均沿 spec 映射表；新增两处显式差异记录——①弃读处置：OkHttp `close()` 同步排空 ↔ moonhttp `dispose()` 异步排空（单线程协程模型的结构化并发约束，R3）；②仅 `drop()` 不收尾 ⇒ 租约滞留（OkHttp 有 GC 弱引用泄漏检测，MoonBit 无——文档化 + F9 欠账）。`execute` 直通无 Dispatcher 闸门已在 FR-013 登记 |
| IV 验收场景与测试先行 | 通过：FR/US ↔ 元测试映射表（下）；断言优先 `assert_eq`/`assert_true(err is …)`；全部基于 P03 本地夹具；禁 sleep——取消/滴流场景以夹具节奏与读边界推进 |
| V Target 策略 | 通过：native/wasm 双绿门；js 仅编译检查不入门禁、零 js 分支、欠账 F9 延续；wasm-gc 排除（上游缺口） |
| VI 简洁与接口纪律 | 通过：client 冻结面 = FR-014 最小集 + 2 错误变体；core 增面 = FR-015 裁决最小形状（1 参 1 法）；`HttpClient` 不建 P08 配置位字段（YAGNI）；`.mbti` 逐次审视入六门，契约见 contracts/call-api.md |
| VII 中文表达 | 通过：注释/文档全中文；Conventional Commits 中文描述 |

**Phase 1 复核**：设计落定后无新增违宪点。需持续盯防项＝①取消收尾路径
混入 async 操作（会把 I-6 破坏成 flaky）；②body 阶段 cancel 误触已归池
连接（I-3 的 lease 置 None 时序是实现正确性的支点）。

## Project Structure

### Documentation (this feature)

```text
specs/005-m1-p05-call-engine/
├── spec.md                    # clarify 已闭（C2/C3 裁决）+ FR-015 回记
├── plan.md                    # 本文
├── research.md                # R1–R8：取消底座/@http 锚点/dispose 裁决/夹具/js/测试
├── data-model.md              # 五实体/七不变量/两张状态迁移图
├── contracts/
│   └── call-api.md            # client 冻结面 + core 裁决面（SC-007 对账面）
├── quickstart.md              # 六门 + 分场景 + js 非门禁项
└── checklists/requirements.md # 16/16（specify 阶段产物）
```

### Source Code (repository root)

```text
src/
├── client/                        # 门面包（池已在此；同包私有能力复用）
│   ├── moon.pkg                   # 零改动（async/async/http/fixtures 已具备）
│   ├── http_client.mbt            # 新：HttpClient/Call/错误变体/cancel/execute
│   ├── exchange.mbt               # 新：exchange_once 接缝 + 折叠缓存 + Address 推导
│   ├── body_bridge.mbt            # 新：BodyBridge 读适配器 + 租约处置状态机 + on_dispose 注入
│   ├── call_test.mbt              # 新：US-1/2/3/5 场景（黑盒 P05-US*）
│   └── call_wbtest.mbt            # 新：桩接缝重放/折叠计数/状态机/竞争（白盒 P05-WB*）
├── core/                          # 增面仅限 FR-015 裁决（contracts §2）
│   ├── moon.pkg                   # 零改动
│   ├── response_body.mbt          # 增：stream 的 on_dispose? 参 + dispose 方法
│   └── response_body_lifecycle_test.mbt  # 增：dispose 语义元测试六条（T003）
└── internal/fixtures/             # 期望零 diff（F-8 若触发，增量逐处归因 FR-010）
```

**Structure Decision**: 管线入既有门面包 `src/client`（004 结构裁决延续：
执行管线/池/超时/Dispatcher 同包；与池同包使 Lease 内部连接可直接复用、
`.mbti` 零新增桥接面）。core 增面是 FR-015 显式授权的裁决落地，非泄漏
（P02 契约本就指定 P05 为体生命周期收尾 owner）。夹具零扩展为基线假设
（R6；1xx 组合响应待 implement 首片核实）。

## 四个决策节（细则见 research.md / data-model.md / contracts/）

**(D-1) 研究与决策记录 → research.md R1–R8**：R1 取消底座（with_task_group
+ Task 句柄 + handle_cancellation 判别；组生命周期硬约束）＋R2 @http 管线
锚点表（end_request 1xx 跳过、skip/close、帧形态归 P02）＋R3 dispose 裁决
（C2 支点触发）＋R4 三通道落点＋R5 折叠缓存与接缝＋R6 夹具适配（F-8 待核）
＋R7 js 口径＋R8 测试组织。

**(D-2) `.mbti` 冻结面 → contracts/call-api.md**：client =
HttpClient（new/new_call）+ Call（execute/cancel/is_cancelled）+
CallCancelled/CallStateError；core = stream 增 `on_dispose?` + `dispose`
（且仅此）；fixtures 零 diff（F-8 例外须归因）。

**(D-3) 数据模型 → data-model.md**：五实体（HttpClient/Call/exchange
接缝/BodyBridge/错误变体）、七不变量（I-1 一次性、I-2 折叠一次、I-3 租约
唯一处置、I-4 归池前提、I-5 取消幂等、I-6 收尾仅同步、I-7 公开面零泄漏）、
Call 状态机与租约处置状态机两张迁移图。

**(D-4) 取消三通道 → research R4 + data-model §3**：标记（execute 首检 +
读边界检查）/ 在途取消（Task::cancel + handle_cancellation→None→
CallCancelled）/ 毒化（exchange 收尾与 body 阶段 cancel 的 poison+release，
I-3 时序保证迟到 cancel 安全）。

## FR/US ↔ 元测试映射表（包级 DoD 对账面）

| spec 条目 | 元测试（文件·盒型） | 状态 |
| --- | --- | --- |
| FR-001/US-2 一次性 | call_test·黑盒（P05-US2*：完成/失败/取消后二次 execute→CallStateError） | 计划 |
| FR-002a/US-3-1 预取消 | call_test·黑盒（execute 首检，accepted_total==0） | 计划 |
| FR-002b/US-3-2 写中取消 | call_test·黑盒（SlowReceive+大 body；CallCancelled+池计数） | 计划 |
| US-3-3 读中取消 | call_test·黑盒（Drip 滴流；边界失败+毒化） | 计划 |
| FR-003 判别性 | call_test·黑盒（`err is CallCancelled` vs PartialResponse 协议错误） | 计划 |
| FR-004/US-4 零折叠 | call_wbtest·白盒（桩接缝 N 次重放；fold_count==1 + raw 两两 assert_eq） | 计划 |
| FR-005/US-5 体生命周期 | call_test·黑盒（三路径 + 池计数双证据；场景 2 用 dispose） | 计划 |
| FR-006 接缝/单轮 | call_wbtest·白盒（exchange_once 直调）+ implement 面审（execute 无循环） | 计划 |
| FR-007 Connection:close | call_test·黑盒（close_after_response；读完 close 不回池，新建+1） | 计划 |
| FR-008/SC-007 冻结面 | moon info 对账 contracts §1/§2 | 计划 |
| FR-009/US-1 帧形态 | call_test·黑盒（CapturedRequest.chunked：Stream→true、Bytes→false） | 计划 |
| FR-010 1xx 透传 | call_test·黑盒（F-8 组合响应；缺省回调不暴露） | 计划（夹具待核 R6） |
| FR-011 非取消错误毒化 | call_test·黑盒（RST/断连→错误透传+不回池） | 计划 |
| FR-012 竞争/幂等 | call_wbtest·白盒 + call_test 黑盒（读到底→release→迟到 cancel→复用不新建） | 计划 |
| FR-013 并发语义 | 文档项（API 文档显式声明无闸门）+ 并发 Call 互不干扰冒烟 | 计划 |
| FR-015/C2 dispose | contracts §2 面审 + US-5 场景 2 承载 | 计划 |
| SC-001/SC-006 双 target | quickstart §1（六门） | 计划 |

## 验收口径（收口六门 + 专项；命令全录 quickstart.md）

### 收口六门

1. `moon check --target native --deny-warn`
2. `moon check --target wasm --deny-warn`
3. `moon test --target native --deny-warn`
4. `moon test --target wasm --deny-warn`
5. `moon fmt --check`
6. `moon info` 后审 `.mbti` diff（client = contracts §1；core = §2 且仅此；
   fixtures 零 diff；最终轮先 `moon clean`）

js 非门禁：`moon check --target js`（+可行时 node 冒烟）。

### ⚠️ `-p` 假验证警示

`moon test -p` 只认包名（`hahh9527/moonhttp/client`）；目录路径跑 0 个
测试却 exit 0。执行后检查 `Total tests:` 非 0（quickstart §0）。

## 收尾事项

1. 六门全绿 + `.mbti` 对账结论归档（client/core/fixtures 三面对账）。
2. spec 回记核验：FR-015 裁决面（dispose 形状）与 Assumptions C1/C2 的
   plan 核实结果已在本 plan 期写回 spec（随本 plan 交付）。
3. F-8（1xx 组合响应夹具）核实结论归档：支持→零改动；不支持→最小扩展
   归因 FR-010。
4. `placeholder` 保留（P6 延续）；删除评估留后续收口片。

## Complexity Tracking

> 无 MUST 级违例；一条归属表述张力按例外跟踪（下表首行，2026-10-25
> analyze 裁定入册）。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 归属表述张力：宪法「技术约束·分层」括号将「Call 与取消」列于 core 包，本包按 004 结构裁决把执行管线（HttpClient/Call/exchange/取消）落门面包 `src/client`（依赖方向仍单向向下，无 MUST 冲突） | 与池同包使 Lease 内部连接直接复用、`.mbti` 零新增桥接面（004 plan 结构裁决先例；`docs/roadmap/M1/README.md` 第 2 节 P04–P09 入门面包） | core 托管需新增 client↔core 桥接公开面，反增接口面（宪法 VI） |
| 性能基准数据延后：FR-004/L3 为机制级交付（SC-004 计数+字节级断言），量化门禁整体归 P10 重定向/重试基准（宪法 II） | 机制断言可先于真实重定向逻辑独立验收（US-4 桩接缝）；P10 基准消费本包折叠缓存杠杆 | 本包内引入延迟断言会被基准抖动侵蚀测试稳定性（spec「性能影响」节已记录） |
| （无其他） | — | — |

## 风险登记（plan 视角最高风险三处）

| # | 风险 | 影响 | 处置 |
| --- | --- | --- | --- |
| R1 | Dropped→skip 的异步落点误设计成「组内收留」或「惰性 skip」——结构化组返回即终止（task_group.mbt:105-110），两类方案都不成立 | US-5/SC-005 正确性 | 已裁决：dispose 显式异步收尾（R3），消费者协程同步推进，测试零 sleep；毒化保底仅作 skip 失败分支 |
| R2 | body 阶段 cancel 与体处置竞争：迟到 cancel 误杀已归池连接（串响应级事故） | FR-012/池正确性 | I-3 时序：处置完成即置 lease=None，cancel 见 None 即 no-op；处置动作全部经 P04 幂等 Lease；白盒竞争专项（P05-WB*） |
| R3 | 1xx 组合响应超出 P03 单响应脚本模型（status=100 合法性/序列推进未核） | FR-010 验收 | implement 首片核实；兜底：夹具最小扩展（裸写状态线）逐处归因 FR-010；语义本身透传 @http（client.mbt:237-251 已锚定），测试失败不阻塞其余场景 |
