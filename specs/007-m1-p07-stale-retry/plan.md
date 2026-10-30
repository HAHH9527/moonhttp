# Implementation Plan: 连接失败重试 stale-retry（M1-P07）

**Branch**: `007-m1-p07-stale-retry` | **Date**: 2026-10-30
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from
`/specs/007-m1-p07-stale-retry/spec.md`
（含 2026-10-30 Clarifications：种子 C1–C4 与证据裁决 R1/R2 已回记；
qodercn 独立复核六项阻断修正已采纳——F17 口径统一、FR-007 轮内
尝试子循环、FR-003 保守封锁口径、US-4-1 可达形态、TLS 证书族差异
登记、js 编译面声明。全部自主裁决已闭，无 [NEEDS CLARIFICATION]）

**Note**: 全部源码级证据与决策（R1–R11）在 research.md，本文引用不重复。

## Summary

在 P06 follow-up 循环内落地 OkHttp `RetryAndFollowUpInterceptor.recover`
等价物：轮内**尝试子循环**（每请求代次至多 2 次尝试，1 原始 + 至多 1
重试，不重入外层循环、不占 20 跳预算）。阶段化错误捕获（建连/发头/
写体/读头，L1 自有调用点边界）+ 两层判定器（错误族检测按 target 分
文件；决策函数纯函数全分支可测）按六条件合取分流：EOF 族（
`ReaderClosed`/`OSError`/TLS 族）可重试并判 stale（毒化 + 
`stale_evictions` +1）；协议错误族（`BadRequest`/`HttpVersionNotSupported`/
`IncorrectBodyLength`）不可重试但毒化照常；`Stream` 体已进入发送保守
封锁。重试同代次（gen 不变、折叠缓存复用、线上字节逐字节一致）、
错误原样透传、取消优先。`HttpClient::new` 增可选参
`retry_on_connection_failure~`（缺省 true）为唯一公开面增量。

## Technical Context

**Language/Version**: MoonBit，moon ≥ 0.1.20261012（003 已核证口径，
与 P05/P06 同仓一致）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（registry 钉版）；
仅用 `@async`/`@http`/`@io`/`@os_error`/`@tls`/`@socket` 公开 API；
本模块 core 包（P01/P02 已交付）；零新增外部依赖（moon.pkg 新增三
个上游包 import，均为同一上游模块内包）

**Storage**: N/A（纯内存编排）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；命名
`P07-<域><序> 描述`（P05 R8 惯例延续）；判定器两层——决策函数白盒
全覆盖，族检测不可构造分支记诚实边界（research R4）

**Target Platform**: native + wasm 双绿为门；js **未验证**（仅
`moon check --target js`；判定器按 target 分文件——native/wasm 全量
分类 + js 降级透传，R6；@http 自身 client.js.mbt 先例）；wasm-gc 排除

**Project Type**: library（门面包 `src/client` 增量；core 零 diff）

**Performance Goals**: 快乐路径零新增成本（判定器仅错误路径执行，无
热路径新增分支/分配）；stale 场景代价 ~1 次额外 RTT（02 §6，池化
必要配套）；重试复用同代次折叠缓存（零重折叠）；量化归 P10

**Constraints**: 全程公开 API（宪法 I）；进入重试分支前旧租毒化必
已完成（FR-007 底线）；计数与重试结果无关（FR-004）；取消优先于重
试（FR-006）；重试不改请求/代次（FR-009）；公开面增量恰为
`HttpClient::new` 可选参数（FR-011 冻结面）；`src/client/placeholder`
原样保留

**Scale/Scope**: `src/client` 增 3 文件（recover.mbt〔全 target：枚
举+decide 纯函数〕、recover_family.mbt〔[native,wasm] 族检测，
moon.pkg targets 表显式锁定〕、recover_family.js.mbt〔js 降级，后缀
自动锁〕、recover_wbtest.mbt 白盒）+ 改 4 文件（http_client.mbt 增
HttpClient/Call priv 字段与构造参数、exchange.mbt 阶段标记插桩、
follow_up.mbt 尝试子循环接线（errdefer 上移）、client.mbt 增
note_stale_hit 私有入口）+ moon.pkg（3 import + targets 表）；测试
改 2 文件（call_test.mbt 增补、follow_up_wbtest.mbt 增补）；
`src/internal/fixtures` 原则零增量（优先路径＝Capture 两跳 run()，
探针不合才引入新变体——research R7 比选）；specs/006/data-model.md
D-2 加注；codemap 收尾订正。FR-001～FR-011、SC-001～SC-008
（T0 基线实测订正：js check 基线即红——13 个既有错误，P07 过门
条件＝零新增 js 错误，见 contracts §5）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过**：全部设计仅经上游公开 API（research R2 锚点表）；不 fork/复制/vendor；上游改动与 issue/PR 零需求（RST 能力缺口维持欠账 F16，不发起）。**显式否决①**：改 `BodySource::Stream` 回调签名以精确计数写调用——动 core 公开面、违 FR-011 冻结意图，改用「filler 调用即置位」保守口径（R3）。**显式否决②**：为 refused-connect 恢复半边构造竞态注入——违可控服务端原则（spec R2） |
| II 性能优先 | 通过：判定器仅错误路径执行；stale 恢复是池化判据的必要配套（02 §6）；重试同代次零重折叠；量化归 P10；本包测试不断言延迟数字 |
| III OkHttp 语义对齐 | 通过：六条件判定式/recover 门/one-shot 封锁/毒化解耦全部 5.5.0 锚点对拍（spec 映射表）；显式差异五处——①max_attempts=2 显式化（替代 RouteSelector 耗尽）；②TLS 证书族暂按可重试（:183-193 实况为不可重试，M2/M3 复核收窄）；③408/503/421 响应级重试不做（D7）；④`Stream` 封锁口径为「体发送已进入」保守化（OkHttp requestSendStarted 按异常类型）；⑤总线上请求数上界 ≤42（006「21」口径修正，spec Assumptions） |
| IV 验收场景与测试先行 | 通过：FR/US ↔ 元测试映射表（research R10）；红-绿循环优先区＝判定器分支与子循环接线；决策函数全分支白盒用例；族检测不可构造分支（TLS 族/ResolveHostnameError/`BadRequest` 跨包不可构造——pub 非 pub(all)）以集成场景（B-11）+ 诚实边界记录覆盖（R4）；全部基于 P03 本地夹具 |
| V Target 策略 | 通过：native/wasm 双绿门；js 仅编译检查——判定器按 target 分文件（recover.mbt〔native,wasm〕/ recover.js.mbt〔js〕，上游 client.mbt/client.js.mbt 同款机制），js 语义＝重试不激活（R6）；wasm-gc 排除 |
| VI 简洁与接口纪律 | 通过：client 公开面增量 = 且仅 = `HttpClient::new` 可选参数（contracts §1 对账面）；新增全部为 priv（Call 3 字段、ConnectionPool::note_stale_hit、判定器/族枚举）；core 零 diff；stale 计数入口同包私有（不设公开 setter）；`@async.retry` 不引入（YAGNI，max_attempts=2 无退避） |
| VII 中文表达 | 通过：注释/文档全中文；Conventional Commits 中文描述 |

**Phase 1 复核**：设计落定后无新增违宪点。需持续盯防项＝①重试分支
漏毒化（旧租未 close 就取新租——守恒恒等式仍成立但连接泄漏）；
②`stream_body_written` 未按 attempt 复位（误封锁下一 attempt）；
③stale 计数误入不可重试路径（FR-004 反向）。

## Project Structure

### Documentation (this feature)

```text
specs/007-m1-p07-stale-retry/
├── spec.md                    # clarify 已闭（C1–C4/R1/R2 + qod-1 六修正）
├── plan.md                    # 本文
├── research.md                # R1–R11：落位点/判定器形状/夹具设计/js 形态/错误构造性
├── data-model.md              # 判定决策矩阵/子循环状态迁移/不变量 INV-R1..R5
├── contracts/
│   └── retry-api.md           # client 公开面增量契约 + priv 接缝 + 夹具增量（SC-008 对账面）
├── quickstart.md              # 六门 + 分场景跑法
└── checklists/requirements.md # 全过（specify 阶段产物，qod-1 后视为通过）
```

### Source Code (repository root)

```text
src/
├── client/                          # 门面包（同包私有能力复用）
│   ├── moon.pkg                     # 改：+3 import；+options(targets) 表（recover_family.mbt 锁 native,wasm）
│   ├── http_client.mbt              # 改：HttpClient::new 可选参 + HttpClient priv 字段（开关不进 Call）
│   ├── client.mbt                   # 改：ConnectionPool::note_stale_hit（priv，锁内 +1）
│   ├── exchange.mbt                 # 改：阶段标记插桩（last_stage 前置赋值 + filler 置位）
│   ├── follow_up.mbt                # 改：errdefer 上移 + 轮内尝试子循环 + recover 接线
│   ├── recover.mbt                  # 新（全 target）：SendStage/ErrFamily/RetryDecision + decide 纯函数
│   ├── recover_family.mbt           # 新〔targets 锁 native,wasm〕：error_family 段相关分类
│   ├── recover_family.js.mbt        # 新〔js 自动〕：error_family 降级恒 Other
│   ├── call_test.mbt                # 改（在场，增补）：US-1~US-4 场景（黑盒 P07-US*）
│   ├── call_wbtest.mbt              # 改（在场，如需）：构造参数适配（尾随可选参零改动兼容，qod-2 点 4 已核）
│   ├── follow_up_wbtest.mbt         # 改（在场，增补）：errdefer 正方向钉用例 + 子循环接线（白盒 P07-WB*）
│   └── recover_wbtest.mbt           # 新：decide 矩阵全分支 + 可构造族直测（白盒 P07-WB*）
├── core/                            # 零 diff（contracts 显式声明）
└── internal/fixtures/               # 原则零增量（R7 优先路径＝Capture 两跳 run()）；
                                     #   仅当 canned 帧探针不合才引入新变体（raw_peer.mbt + .mbti）
```

**Structure Decision**: recover 入既有门面包 `src/client`（P06 结构
裁决延续：`exchange_loop` 是接缝，尝试子循环为其轮内扩展，同包直读
`lease.addr`/池计数先例在场）；判定器独立成文件对（recover.mbt/
recover.js.mbt）仅为 target 分文件所需，逻辑量小、不设新包。
实现顺序：T0 基线 → 判定器（纯函数红绿）→ 接线 → 夹具 → 集成场景
→ 收尾（006 加注/codemap/六门）。

## Complexity Tracking

> 无违宪项。例外跟踪延续项：`src/client/exchange.mbt:90` 的
> `#warnings("-unused_value")` 定点抑制（006 converge 遗留，本包不
> 动其语义）；js `unused_package` 已由包级既有抑制覆盖（contracts
> §5）。**T0 基线记录（2026-10-30）**：native/wasm check+test 全绿
> （276/276）；js check 基线即红（13 个既有错误——P06 承诺未达成
> 的存量，非本包回归），P07 过门＝零新增 js 错误。P08 前瞻欠账一
> 行：组级取消与重试子循环的接线归 P08 callTimeout/取消伞对拍。
