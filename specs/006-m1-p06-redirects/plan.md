# Implementation Plan: 自动重定向 follow-up 循环（M1-P06）

**Branch**: `006-m1-p06-redirects` | **Date**: 2026-10-27
**Spec**: [spec.md](spec.md)

**Input**: Feature specification from
`/specs/006-m1-p06-redirects/spec.md`
（含 2026-10-27 Clarifications 七条裁决：C1 剥头范围、C2 降级集合
5.5.0 对拍修正、300 跟随修正、C3 上限固定、C4 代次粒度方向、上限
精确语义、one-shot 对拍；全部自主裁决已回记 spec）

**Note**: 全部源码级证据与决策（R1–R10）在 research.md，本文引用不重复。

## Summary

在 P05 exchange 接缝上落地 OkHttp `RetryAndFollowUpInterceptor` 的
重定向半边：`Call::execute` 的组内子任务从单轮 `exchange_once` 换为
follow-up 循环——每轮前 guard 取消 → 单轮 exchange → 决策表（M1 版，
5.5.0 对拍）判定 → 中间响应 `skip_response_body` 排干 → 同 host 保持
租约 / 跨 host 干净归还后换租 → prior 链累积 → 终态响应挂链返回；
20 跳上限超出 raise `TooManyFollowUps`。决策表行为、上限语义、one-shot
（Stream 不可重放）处置均以 tag `parent-5.5.0` 源码对拍为基准；跨 host
剥 `Authorization`+`Cookie` 为 M1 无 CookieJar 的有意差异（M2/11-cookies 回改）。
L3 折叠缓存升级为请求代次粒度（C4）。client 公开面增量 = 且仅 =
`TooManyFollowUps` 错误变体。

## Technical Context

**Language/Version**: MoonBit，moon ≥ 0.1.20261012（003 已核证口径，
与 P05 同仓一致）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（registry 钉版）；
仅用 `@async`/`@http` 公开 API；本模块 core 包（P01/P02 已交付）；
**零新增外部依赖**

**Storage**: N/A（纯内存编排）

**Testing**: moon test（黑盒 `_test.mbt` / 白盒 `_wbtest.mbt`）；决策表
逐行基于 P03 夹具；命名 `P06-<域><序> 描述`（P05 R8 惯例延续）

**Target Platform**: native + wasm 双绿为门；js **未验证**（仅
`moon check --target js`，零 `#cfg(js)` 分支——js 上 @http 走 fetch
`redirect:"follow"`，浏览器已跟随 ⇒ 循环首轮即终态，R8）；wasm-gc 排除

**Project Type**: library（门面包 `src/client` 增量；core 零 diff）

**Performance Goals**: 宪法 II 防退化两项带验收断言——中间 body 排干
O(body)（SC-006 干净流）、同 host 租约保持消除归还-重取（SC-003 连接
计数）；L3 代次重折叠每代次恰一次（follow-up 路径不重复折叠同一请求）

**Constraints**: 全程公开 API（宪法 I）；每轮 guard 取消（FR-001，裸
`CallCancelled`）；排干先于换代（INV-2）；上限计数语义对齐 5.5.0
（R1：响应到达后、发送前检查，至多 20 个 follow-up）；禁 sleep 串联；
`src/client/placeholder` 原样保留

**Scale/Scope**: `src/client` 增 2 文件（follow_up.mbt、
follow_up_wbtest.mbt）+ 改 5 文件（http_client/exchange/body_bridge
小步重构、call_test.mbt 增补、call_wbtest.mbt 适配 exchange_once
直调点——后三者 P05 已在场非新建，round8 I1 补账）；`src/core`
零改动；FR-001～FR-012、SC-001～SC-008
（2026-10-28 review 修复批实测订正：body_bridge.mbt 最终零 diff；
实际改动集另含 internal/fixtures/scripted_server.mbt——T019 观测面
+31 行与 review 修复批 mount_truncated `derive_close~` 参数，见
contracts §3 登记例外；原清单漏列该文件、多列 body_bridge.mbt）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 对照结论 |
| --- | --- |
| I 非侵入底座（不可妥协） | **通过**：全部设计仅经 `@async`/`@http` 公开 API（R2 锚点表）；不 fork/复制/vendor；上游改动与 issue/PR 零需求。**显式否决①**：跳过 Lease 直接持 `@http.Client` 跨轮复用——破坏 P04 池契约与毒化语义。**显式否决②**：为「js 关闭浏览器自动跟随」patch @http——02 §5 判为侵入，js 形态按宪法 V 记未验证 |
| II 性能优先 | 通过：租约保持（FR-007）与排干（FR-002）均有验收断言；L3 代次缓存消除 follow-up 路径重复折叠；循环自身零轮询（O(1) 标记 + Task 句柄）；量化归 P10 |
| III OkHttp 语义对齐 | 通过：决策表/上限/Location/one-shot 处置全部 5.5.0 源码对拍（R1 file:line 锚点）；四处显式差异记录——①跨 host 剥 Cookie（M1 无 Jar 等价保守化，M2/11-cookies 回改）；②`TooManyFollowUps` 变体替代 ProtocolException 消息判别；③M1 无 followRedirects/followSslRedirects 开关（= OkHttp 默认 true 行为面，归 P08）；④401/407/408/503/421 终态透传（Authenticator 随 M2/08，重试归 P07——5.5.0 实况已录 spec 映射表供 P07 消化） |
| IV 验收场景与测试先行 | 通过：FR/US ↔ 元测试映射表（research R10）；决策表每行 ≥1 用例（SC-001）；断言优先 `assert_eq`/`assert_true(err is …)`；全部基于 P03 本地夹具 |
| V Target 策略 | 通过：native/wasm 双绿门；js 仅编译检查（R8：循环零 js 分支、浏览器行为保证直通语义）；wasm-gc 排除 |
| VI 简洁与接口纪律 | 通过：client 公开面增量 = 且仅 = `TooManyFollowUps`（contracts 对账面）；循环为纯上层包裹（`exchange_once` 单轮语义不动，仅参数化）；Call 新增 3 个 priv 字段全内部（租约地址经 `lease.addr` 同包直读，不设镜像字段——round3 D-4 订正）；夹具零扩展基线假设（R7 全能力在场）（2026-10-28 订正：该假设已被 T019 owner 裁决①与 review 修复批两次登记性例外打破，见 contracts §3） |
| VII 中文表达 | 通过：注释/文档全中文；Conventional Commits 中文描述 |
| 零警告门依赖定点警告抑制 | ⚠️ 例外跟踪：`src/client/exchange.mbt:90` 的 `#warnings("-unused_value")` 定点抑制（converge F3 → T021 登记，2026-10-28）——T004 起 execute 的 spawn 换靶 `exchange_loop`，`exchange_once` 在非测试源零调用点、降为 spec 钦定白盒直调接缝（plan Structure Decision），白盒 `_wbtest` 直调不计入 lib 构建使用判定 ⇒ `--deny-warn` 门下 [unused_value] 必触发；公开面冻结（contracts §1）排除改 pub 出口。依据与替代方案否决详见文末「例外跟踪」 |

**Phase 1 复核**：设计落定后无新增违宪点。需持续盯防项＝①换代前排干
缺失（会毒化下轮请求字节流——INV-2）；②中间响应事件误触发
（bridge 体不交付不 dispose，直接 conn 上 skip——R6 证据）；③
`conn_close_seen` 清理时机（ensure_lease 取新租时复位——I-7）。

## Project Structure

### Documentation (this feature)

```text
specs/006-m1-p06-redirects/
├── spec.md                    # clarify 已闭（七条裁决回记）
├── plan.md                    # 本文
├── research.md                # R1–R10：5.5.0 对拍/落位点/重构形状/夹具/js/错误面
├── data-model.md              # 六实体/七不变量/轮循环与租约三态图
├── contracts/
│   └── follow-up-api.md       # client 公开面增量契约（SC-008 对账面）
├── quickstart.md              # 六门 + 分场景跑法
└── checklists/requirements.md # 16/16（specify 阶段产物）
```

### Source Code (repository root)

```text
src/
├── client/                          # 门面包（同包私有能力复用）
│   ├── moon.pkg                     # 零改动
│   ├── http_client.mbt              # 改：Call 增 3 priv 字段；execute spawn 换 exchange_loop
│   ├── exchange.mbt                 # 改：exchange_once/exchange_with_lease 参数化（request 代次）
│   ├── body_bridge.mbt              # 改： folded_headers 代次键化（挪至本文件或 exchange 内聚处，implement 定）
│   ├── follow_up.mbt                # 新：决策表 + follow-up 循环 + 头改写 + prior 链 + 排干/租约保持
│   ├── call_test.mbt                # 改（P05 已在场，增补）：US-1~US-6 场景（黑盒 P06-US*）
│   ├── call_wbtest.mbt              # 改（P05 已在场，增补）：T003 适配 exchange_once 直调点（补 request 实参）
│   └── follow_up_wbtest.mbt         # 新：决策表真值/代次缓存/上限计数/竞争（白盒 P06-WB*）
├── core/                            # 零 diff（contracts 显式声明）
└── internal/fixtures/               # 期望零 diff（R7：全部所需能力已在场）
```

**Structure Decision**: 循环入既有门面包 `src/client`（P05 结构裁决
延续：`exchange_once` 是 spec 钦定接缝，循环为其纯上层包裹，同包直读
Call/Lease 私有状态；`.mbti` 增量收敛到单一错误变体）。P05 白盒对
`exchange_once` 的直调路径以「补 request 实参」方式最小适配（签名
参数化，单轮语义不变）。

### `.mbti` 对账基线口径（round8 W2 登记）

- contracts §2/§3「零 diff」对账基线 = **git HEAD 提交态**，不取
  工作区现状（§1 client 增量对账同理以 HEAD 为底）。
- 当前工作区 3 份 `pkg.generated.mbti`（client/core/fixtures）的
  `Int→Int32` 签名改写 = 本地工具链 `moon info` 再生成的显示差异：
  未提交、无任何 `.mbt` 源码改动伴随、非 P06 任务产物（round7 W2
  实测归因）。
- 该漂移**不随 P06 交付、T001 不入账**：T001 建立基线时以 git HEAD
  版本为准记录（快照若含未提交漂移，须在 baseline.md 显式标注为
  工具链差异）；T017 收口六门以**提交时门复验**为准。
- 本口径仅登记，不改动任何 `.mbti` 文件（宪法 VI：公开面变化必须
  是有意识的决定，而非意外泄漏）。
- （2026-10-28 review 修复批订正）实际交付态与上述「不随 P06 交付、
  不提交」口径不符：`moon info` 为宪法工具链规定收尾步，本机再生成
  必然重写 `Int→Int32` 漂移行并随 P06 入库；client 语义增量
  （`TooManyFollowUps` 两件套）与 fixtures `captured_request_heads`
  （T019 契约 §3 例外）同批提交。宪法 VI「公开面变化必须是有意识的
  决定」以本条订正 + baseline.md T017「.mbti diff 审视」订正节为
  有意识决定载体；原 W2 口径按登记保留、以本条为准。

## 四个决策节（细则见 research.md / data-model.md / contracts/）

**(D-1) 研究与决策记录 → research.md R1–R10**：R1 5.5.0 对拍真值
（决策表/上限/one-shot/剥头范围/408/503/421 实况）＋R2 循环落位与
取消接线＋R3 接缝参数化与 Call 新字段＋R4 Location/头改写/重组矩阵
＋R5 prior 链构建＋R6 排干与租约保持＋R7 夹具能力核证＋R8 js 形态
＋R9 错误面＋R10 测试映射。

**(D-2) 设计与数据模型 → data-model.md**：六实体（循环/代次/决策表/
prior 链/错误变体/Call 内部字段）＋七不变量（INV-1..7）＋轮循环图与
租约 keep/swap/poison 三态。

**(D-3) 接口契约 → contracts/follow-up-api.md**：client `.mbti` 事前
对账面（增量 = 且仅 = `TooManyFollowUps` + to_repr extend；core 零
diff）；行为契约速查表（FR → 语义）。

**(D-4) 验证指南 → quickstart.md**：六门跑法 + US 分场景命令 +
js 非门禁项说明。

## Complexity Tracking

> 无违宪项，表格留空（「零警告门依赖定点警告抑制」为 ⚠️ 例外跟踪态，
> 非违宪项——登记见宪法核查表与文末「例外跟踪」节）。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无） | | |

## 例外跟踪

- **`exchange_once` 定点警告抑制（`#warnings("-unused_value")`，
  `src/client/exchange.mbt:90`；converge F3 → T021，2026-10-28 登记）**：
  - **成因**：T004 起 `Call::execute` 的 spawn 目标换为 `exchange_loop`
    （follow_up.mbt），`exchange_once` 在非测试源零调用点，仅
    `call_wbtest.mbt`（:366/:378/:633——T003 参数化适配后的 P05 白盒
    直调点）直调；白盒 `_wbtest.mbt` 不入 lib 构建使用判定 ⇒ lib 构建
    `--deny-warn` 触发 [unused_value]。成因已由源码「T017 收口注」
    写明（exchange.mbt:85-89）。
  - **为何不改形状**：该函数是 spec 钦定接缝（plan Structure
    Decision「循环为 exchange 接缝的纯上层包裹」）与 P05 单轮语义
    回归锚点。改 pub 违反 contracts §1 冻结面（FR-012/SC-008）；
    删除/内联则丢失白盒回归面；改由循环调用不可行——`exchange_once`
    自带 `pool.acquire`，而循环持租约跨轮（ensure_lease/排干/换租），
    经它发送会破坏租约三态（INV-1/INV-6）。
  - **形态**：声明级 `#warnings("-unused_value")` 定点抑制（非包级），
    语义与签名零变化。
  - **先例**：specs/002 plan「零警告门依赖包级警告抑制」
    （`-reserved_keyword`，owner 2026-10-16 确认保留）。
