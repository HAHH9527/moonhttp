# Implementation Plan: 四类超时与 per-call 配置（M1-P08）

**Branch**: `008-m1-p08-timeouts` | **Date**: 2026-10-30
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from
`/specs/008-m1-p08-timeouts/spec.md`
（v2：种子 C1–C4 与证据裁决 R3/R4 已回记；qodercn 复核 qod-1 八阻断
B1–B8 + 十二建议 S1–S12 全部采纳——取消语义结构保证、call 伞逸出形
态钉定、连接伞竞态清理、写载体钉定 Stream、嵌套归属改写、js 降级弱
化形态、尾刷归读窗、种子偏差 D 表。增补 C5/R5/R6 裁决。全部自主裁
决已闭，无 [NEEDS CLARIFICATION]）

**Note**: 全部源码级证据与决策（R1–R12）在 research.md，本文引用不
重复。

## Summary

在 P05–P07 管线上以**包裹层**叠加 OkHttp 四类超时：④ call 伞（看门
者 + 标记位 + 取消收尾选变体，覆盖 execute 全程含 follow-up/重试，
到期时序准、终态恰为 `HttpTimeout::Call`、用户取消不被吞）；① 连接
伞（ensure_lease 侧包 acquire，含 DNS，池零手术）；② 写窗（header/
Bytes 直包，Stream 经 `@io.Writer` trait 门面逐用户写一窗）；③ 读窗
（end_request 收头单窗 + BodyBridge read_checked 体读包窗，毒化免费
复用）。超时以 `HttpTimeout{Connect/Write/Read/Call}` 显式变体暴露，
判定器族落点三行接入（Connect→建连族可重试，余三者不可重试透传，
decide 零改动）。同时交付 per-call 配置面：`Timeouts` 配置标量 +
`HttpClientBuilder`（共享 pool 引用语义、覆盖标量、负值构建期快速失
败）+ `Request::new_builder()`（headers/tag 保留、换 url/method/
body）+ followRedirects/followSslRedirects 两开关（P06 决策表两门，
F21 回补）。公开面增量恰四项（FR-012）；js 降级清单如实登记（调用方
侧变体、底层 fetch 不保证取消）。

## Technical Context

**Language/Version**: MoonBit，moon ≥ 0.1.20261012（003 已核证口径，
与 P05–P07 同仓一致）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（registry 钉版）；
仅用 `@async`（with_timeout/sleep/with_task_group——全部既有 import）、
`@http`/`@io`（Writer trait 门面——既有 import）等公开 API；本模块
core 包（P01/P02 已交付）；**moon.pkg 零改动**（research R12：零新增
import、targets 表不动）

**Storage**: N/A（纯内存编排）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；命名
`P08-<域><序> 描述`（P05 R8 惯例延续）；判定器矩阵按 S6 收敛口径（四
变体 × 可达段 + 族落点）；计时带断言不对称带（C1：native
[−50,+300]ms、wasm [−50,+1000]ms，证据行登记）；睡眠预算每 target
≤10s（R9 耗时表）

**Target Platform**: native + wasm 双绿为门；js **未验证**（仅
`moon check --target js` 与基线 13 对账零新增；新增代码全 target 中
性、零 #cfg 零 .js.mbt 分文件——R12；js 语义＝调用方侧变体、底层
fetch 不保证取消，FR-011）；wasm-gc 排除

**Project Type**: library（门面包 `src/client` 增量 + core 一函数增
量）

**Performance Goals**: 快乐路径成本＝每操作一 `with_timeout`（实现形
态＝一 TaskGroup + timer 子任务 spawn，非裸 Timer——qod-2 S7 如实表
述；10 §6 预算口径「Timer 创建/取消 ~百 ns 级、块 ≥16KB 占比 <0.1%」
的量级复核归 P10 实测）+ call 伞每 execute 一组（O(1)）；量化归 P10
「超时开/关」对比场景，超出预算则 M2 转 refresh 方案；本包测试不断
言性能数字（计时带为功能正确性）

**Constraints**: 全程公开 API（宪法 I）；包裹层非流程层——仅两处有
界例外（看门者+收尾变体选择、ensure_lease 连接伞位点，FR-002）；
INV-T1..T5（0=无窗/变体恰达/池守恒全交叠/毒化全段覆盖/缺省零扰动，
data-model）；`HttpClient::new` 签名不变（FR-012 冻结底线）

**Scale/Scope**: `src/client` 新增 1 文件（timeout_writer.mbt〔Writer
门面〕）+ 改 5 文件（http_client.mbt〔Timeouts/HttpTimeout/builder 双
构造入口/HttpClient/Call priv 字段/看门者/收尾变体选择〕、follow_up.mbt
〔连接伞包裹 + follow_up_request 两门 + 调用点透传〕、exchange.mbt
〔写窗三接点/读窗收头接点/filler 实参替换〕、body_bridge.mbt
〔read_checked 体读包窗〕、recover_family.mbt〔族落点三行〕）；`src/core` 改 2 文件
（request.mbt 增 `Request::new_builder` + request_test.mbt 派生保留
性断言）；测试改 3 文件 + 新增 1 文件（call_test.mbt 增补、
follow_up_wbtest.mbt 增补、recover_wbtest.mbt 增补、timeout_wbtest.mbt
新〔看门者/门面/池守恒收敛〕）；`src/internal/fixtures`
改 2 文件（scripted_server.mbt 增 **BodyPlan::DripHang**、
**raw_peer.mbt** 增 **PeerProgram::SilentReader**——qod-2 B1 落点修
正）；文档回写四处（P08 种子 D 表八项、F21 两处状态、P06
映射表加注、README 用户文档段）；codemap 收尾订正。FR-001～FR-012、
SC-001～SC-010

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过**：全部设计仅经上游公开 API（research R1–R4 锚点：with_timeout/sleep/task_group 组语义、@io.Writer trait、@http Client 面一律公开调用）；不 fork/复制/vendor；上游改动零需求。**显式否决①**：`with_timeout` 包 execute——上游组 Fail 覆盖语义吞变体（B2 取证），改看门者形态（R1）；**显式否决②**：改 core filler 签名插桩写调用——动 core 公开面，改 trait 门面（R3）；**显式否决③**：acquire 加阈值参数——P04 手术，改 ensure_lease 侧包裹（R2） |
| II 性能优先 | 通过：每操作一 `with_timeout` 的成本（TaskGroup + timer 子任务 spawn，qod-2 S7 如实口径）在 10 §6 量级预算内，P10「超时开/关」实测量化，超出则 M2 转 refresh；热路径有新增分配（Bytes/header 开窗同成本）——如实登记，量化归 P10；门面仅 Stream 体路径构造 |
| III OkHttp 语义对齐 | 通过：四类缺省/0 语义、按操作计时、newBuilder 派生、跟随两门、recover 超时分类全部 5.5.0 锚点对拍（spec 映射表 16 行，两处实测取证）；显式差异七处——①连接伞含 DNS（更严）；②收头单窗粒度（含 1xx）；③写停滞尾刷归读窗；④体消费期不在 call 伞；⑤显式变体替代异常类型判别；⑥js 弱化形态（AbortController 不可触及）；⑦call 伞机制差异（看门者形态，上游 with_timeout 包裹吞变体——实现机制注记非语义差异） |
| IV 验收场景与测试先行 | 通过：FR/US ↔ 元测试映射（research R10）；红-绿循环优先区＝判定器族落点矩阵/决策表两门/看门者标记位三处；计时带不对称带钉死（C1）；睡眠预算表（R9）；全部基于 P03 本地夹具 + 两夹具变体（R8，spec Assumptions 登记） |
| V Target 策略 | 通过：native/wasm 双绿门；js 仅编译检查——新增代码全 target 中性（R12，无 P07 式锁定类型问题）；js 语义＝调用方侧变体（FR-011 弱化形态如实登记，宪法 V 未验证面）；wasm-gc 排除 |
| VI 简洁与接口纪律 | 通过：公开面增量恰四项（contracts §1 对账面；builder 双构造入口计同一语义面）；新增全部 priv（Call 1 字段、看门者/门面/族落点/伞包裹接缝）；`HttpClient::new` 签名不变；Bytes 分块不采纳（R6/spec 非目标） |
| VII 中文表达 | 通过：注释/文档全中文；Conventional Commits 中文描述 |

**Phase 1 复核**：设计落定后无新增违宪点。需持续盯防项＝①看门者标
记位与 execute 终态置位的竞争窗口（WB 竞争断言，research 风险表）；
②Writer 门面漏覆写缺省方法（三方法全覆写 + --deny-warn 门）；③既
有用例在新缺省窗下的回归（R11：预期零回归，首片全量复证）。

## Project Structure

### Documentation (this feature)

```text
specs/008-m1-p08-timeouts/
├── spec.md                    # v2（qod-1 八阻断 + 十二建议采纳）
├── plan.md                    # 本文
├── research.md                # R1–R12：逸出形态/包裹位置/门面/族落点/配置面/夹具/耗时表
├── data-model.md              # 实体 1–7 + 不变量 INV-T1..T5 + 状态迁移图
├── contracts/
│   └── timeout-api.md         # 公开面四项对账面 + priv 接缝表 + 夹具增量 + js 形态 + 质量门
├── quickstart.md              # 六门 + 分场景跑法
└── checklists/requirements.md # 全过（specify 阶段产物，v2 后视为通过）
```

### Source Code (repository root)

```text
src/
├── client/                          # 门面包
│   ├── moon.pkg                     # 零改动（R12）
│   ├── http_client.mbt              # 改：HttpTimeout/Timeouts/HttpClientBuilder + HttpClient/Call priv 字段 + 看门者 + 收尾变体选择
│   ├── timeout_writer.mbt           # 新：@io.Writer trait 门面（写窗逐用户写一窗，R3）
│   ├── follow_up.mbt                # 改：ensure_lease 连接伞包裹 + follow_up_request 两门 + 调用点透传
│   ├── exchange.mbt                 # 改：写窗三接点/读窗收头接点/filler 实参替换（门面）
│   ├── body_bridge.mbt              # 改：read_checked 体读包窗（毒化免费复用）
│   ├── recover_family.mbt           # 改：族落点三行（Connect→ConnectFailure，余→Other）
│   ├── recover_family.js.mbt        # 零改动（js 恒 Other）
│   ├── recover.mbt                  # 零改动（decide 六条件不变）
│   ├── call_test.mbt                # 改：US-1..US-6 黑盒场景增补
│   ├── follow_up_wbtest.mbt         # 改：决策表两门 WB + 连接伞接线伴随
│   ├── recover_wbtest.mbt           # 改：判定器矩阵扩展（S6 口径）
│   └── timeout_wbtest.mbt           # 新：看门者三步序/门面委托/池守恒收敛（R5）
├── core/
│   ├── request.mbt                  # 改：Request::new_builder（五要素保三换）
│   └── request_test.mbt             # 改：派生保留性断言
└── internal/fixtures/
    ├── scripted_server.mbt          # 改：BodyPlan::DripHang 变体（Drip 同族）
    └── raw_peer.mbt                 # 改：PeerProgram::SilentReader 变体
docs/roadmap/M1/P08-timeouts-builder.md   # 回写：种子偏差 D 表八项
docs/roadmap/deferred-items{,-m1}.md      # 回写：F21 状态→已回补
specs/006-m1-p06-redirects/spec.md        # 回写：映射表行加注（008 已交付）
README.md                                  # 回写：超时配置段 + js 降级注记
```

**Structure Decision**: 沿用 P05–P07 单包接线纪律（门面包 client 持
全部超时接线；core 仅一派生构造；fixtures 仅测试基建增量）。Writer
门面独立成文件（timeout_writer.mbt）＝门面三方法 + 委托逻辑内聚，
避免 exchange.mbt 膨胀（007 收尾「文件过大即重组」先例）。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无违宪项） | — | — |

**qod-2 定案记录（2026-10-30）**：两项提请裁决均已定案——① R2 残留
风险关闭（上游 `errdefer proxy.close()`/`errdefer transport.close()`
在场，http/client.mbt:49/:57；论证前提按 S3 修复：acquire 暂停点两
处——池锁 await 取消安全〔mutex.mbt:39-41〕+ 建连 await，两支池状态
均零变化）；② 看门者标记位竞争——单线程协作调度下数据竞争不存在，
残余仅语义竞态，US-5-2 二择一口径已覆盖。plan 两项待裁决清零；qod-2
阻断 B1/B2 修正落笔（夹具落点/枚举归属/run 兜底协调），S1–S11 全部
采纳（R2/R3/R8/R9/风险表/contracts §1–§3 同批回填）。
