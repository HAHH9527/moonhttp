# M2 完整门面——工作包拆分（roadmap）

> 来源：`proj-init-docs/okhttp-on-async-http/README.md` 里程碑 M2。
> 本目录把 M2 拆为 **7 个工作包（P01–P07）**，每个工作包可单独走一遍
> Spec Kit 最小闭环（`specify → clarify → plan → tasks → implement`），
> 并拥有独立、可判定的验收判据。本 README 只做总览与差异登记；
> 各包细节见同目录 `Pxx-*.md`。
> 拆分不修改 `proj-init-docs`（原报告保持原样，以本 README 的差异清单为准执行）。
> 拆分前已核对 M1 欠账 **F1–F6**（总入口
> [`../deferred-items.md`](../deferred-items.md)，明细
> [`../deferred-items/deferred-items-m1.md`](../deferred-items/deferred-items-m1.md)），
> 六条全部纳入本里程碑工作包（见第 2 节清单「回补欠账」列）。

## 1. M2 目标与交付判据（沿用原报告口径）

- **范围**（原报告 §4）：04 拦截器 + 09 请求体构造 + 11 cookies + 08 auth
  + 上游 PR 包（I1/I2）；执行口径另含 M1 划入的 F2 代理支持（D1）。
- **交付判据**：
  1. OkHttp recipes 全套可写（P06 示例集全绿：拦截器三例、请求体家族、
     Cookie、认证）；
  2. 上传 syscall 达标——按 **D3** 口径兑现：本地实验分支（上游副本 +
     I1 补丁）实测达标并归档报告；主分支门禁在 I1 合并发版后启用（**F16**）；
  3. M1 欠账 F1–F6 全部回补（实施完成时在 M1 明细更新状态）；
  4. M1 基线不回归（池化 ≥20× 保持，宪法 II）。
- **人力口径**：原报告 ~16 人日（04+09+11+08 = 15.5 + PR 包 ~0.5）；
  本拆分逐包加总 ≈ **19.5 人日**，差额 ~3.5 人日的构成：
  F2 代理池化 +1d（M1-D3 划入 M2，原 16d 算术未计）、L4 DNS 缓存自组版
  +1d（原算术仅含上游 PR 材料 ~0.5d）、拦截器链化迁移回归 +0.5d（F1 的
  行为等价要求）、P06 recipes 收口与门禁单列 +1d（原报告 recipes 摊在
  04 §3.4 的 0.5d 内，基准复验未计）。

## 2. 工作包清单

| 包 | 名称 | 一句话范围 | 前置依赖 | 人力 | 主要来源 | 回补欠账 |
| --- | --- | --- | --- | --- | --- | --- |
| [P01](P01-request-bodies.md) | 请求体构造器与响应便捷解析 | FormBody/Multipart/File/进度 + json/char_stream | M1-P02, M1-P03 | ~4.5d | 09 全篇 | F4, F5 |
| [P02](P02-proxy-dns-cache.md) | 代理支持与 DNS 缓存 | ProxyConfig/CONNECT 隧道/代理池化 + L4 自组缓存 | M1-P04, M1-P03 | ~2d | 03 §3.5/§3.6 | F2, F3(自组版) |
| [P03](P03-interceptors.md) | 双层拦截器链 | Interceptor/Chain/peek_body + M1 管线链化迁移 | M1-P05, M1-P06, M1-P07 | ~4d | 04 全篇 | F1 |
| [P04](P04-cookies.md) | CookieJar | 接口/内存 Jar/匹配/三格式日期/持久化/Bridge 接线 | P03 | ~3.5d | 11 全篇 | — |
| [P05](P05-auth.md) | 认证 | Authenticator/challenges/401 决策表行/407 绕行 | P03, P02 | ~3.5d | 08 全篇 | F6 |
| [P06](P06-recipes-benchmark-gate.md) | recipes 收口与 M2 门禁 | recipes 全套示例 + 基线不回归 + syscall 度量 | P01–P05 | ~1.5d | README §4、14 §5 | — |
| [P07](P07-upstream-prs.md) | 上游 PR 包 | I1/I2/I5 补丁+基准+文案（**须人工批准**） | P02, P06 | ~0.5d | README §4、14 §3.1 | （F14–F16 的前提） |

依赖关系（`X → Y` 表示 Y 依赖 X）：

- M1-P02/M1-P03 → P01；M1-P04/M1-P03 → P02
- M1-P05/P06/P07 → P03（exchange 接缝 + 循环迁移）
- P03 → P04（Bridge 接线）
- P03、P02 → P05（链上 401 行 + 407 代理场景）
- P01–P05 → P06（收口）
- P02、P06 → P07（自组版对照 + 度量数据）

拓扑分层示意（同层可并行）：

```
层 0（可并行）  P01 请求体构造器   P02 代理与 DNS 缓存
层 1            P03 双层拦截器链
层 2            P04 CookieJar
层 3            P05 认证
层 4（收口）    P06 recipes 与 M2 门禁
层 5（批准后）  P07 上游 PR 包
```

建议实施顺序（`→` 串行，`|` 可并行）：

```
P01 | P02 → P03 → P04 → P05 → P06 → P07
```

（P07 的材料准备可自 P02 交付后随时启动，但提交时点由人工批准决定，
置于收口之后；P06 的 syscall 度量数据是 I1 PR 证据的输入。）

## 3. 与原设计的差异清单（执行以本清单为准）

拆分与裁剪过程中产生的、与 `proj-init-docs/okhttp-on-async-http` 原文的差异，
逐条登记如下（原文不回改）。其中牵扯后续里程碑/上游合并的条目另提取为
跨里程碑跟踪：总入口 [`../deferred-items.md`](../deferred-items.md)，
M2 明细 [`../deferred-items/deferred-items-m2.md`](../deferred-items/deferred-items-m2.md)
（F14–F16）：

| # | 差异 | 原文出处 | 理由与处理 |
| --- | --- | --- | --- |
| D1 | **代理支持纳入 M2 且 CONNECT-only**：原报告 M2 范围文字未列代理（03 §3.6 代理池化在 M1-D3 划入 M2，但 M2 的 16d 算术未计）；本拆分以 P02 交付 ProxyConfig/CONNECT 隧道/代理池化，http-over-proxy absolute-form 不做（依赖 I5），CONNECT-only 降级显式标注 | README §4（M2 范围）；03 §3.6；M1-F2 | 欠账 F2 已承诺 M2 回补，且 407 认证（M2 判据链）依赖代理场景；absolute-form 部分拆出为 **F14**（I5 合并后回补） |
| D2 | **DNS 缓存终态口径 = 自组版**：原报告「PR 期间 L1 用非侵入 DNS 缓存兜底」未定切换时点；本拆分明确主分支在 M2 末仍为自组版（I2 合并发版后才评估切换共享版） | 03 §3.5；14 §6 | 上游合并时点不可控，M2 判据不能悬在上游；切换动作拆出为 **F15** |
| D3 | **上传 syscall 判据的兑现分支**：判据「上传 syscall 达标」以本地实验分支（pull 上游副本 + I1 补丁，宪法技术约束允许）实测归档兑现；主分支 send_buf 维持 1KB 上游现状，门禁常驻化待 I1 合并发版 | 14 §3.1（「L1 侧无绕行……必须上游」）、§5 验收门槛；README §4 判据 | I1 无非侵入绕行，主分支达标在物理上依赖上游；门禁启用拆出为 **F16** |
| D4 | **P07 上游 PR 包扩为 I1/I2/I5**：原报告 M2 范围文字仅「（I1/I2）」；I5 是 03 §3.6 的「建议 M2 提上游 PR」与 F2 回补要点的绑定项 | README §4；03 §3.6；M1-F2 回补要点 | F2 的回补需要 I5 材料同期就绪（否则 absolute-form 无归依）；I5 补丁仅 ~5 行，边际成本可忽略 |
| D5 | **recipes 收口单列 P06**：原报告将 recipes 示例摊在 04 §3.4（0.5d 计入 04 的 3.5d）；本拆分把「recipes 全套可写」判据的示例集与门禁执行集中到 P06 | 04 §3.4；README §4 判据 | 判据需要跨包示例（04/08/09/11 编织），摊在单特性篇内无法验收；M1 P10 先例（基准门禁收口单列） |

M2 内部消化、无欠账的差异：无（D4/D5 均在 M2 内闭环）。

## 4. 补充口径说明（非差异，仅为落地澄清）

- 「09 bodies」按原报告特性目录 folder 09 全量理解（请求体构造器 + 响应侧
  便捷 json/char_stream/下载进度，含 F4/F5 两项 M1 划出项），依据 M2 算术
  （09 = 5d 全额入 M2）。
- 「上游 PR 包（I1/I2）」原报告未给独立人日；本拆分按 14 §2（L5 半天 PR、
  L4 ~1 人日）口径计 ~0.5d 材料准备（不含上游协作与等待）。
- 401/407 决策表回补（F6）落点在 P05，决策表宿主是 M1-P06 交付的
  RetryAndFollowUp 层（M2-P03 链化后为其链上层）——401 行为对 M1 的变化
  仅限「配置了 authenticator 的调用方」，未配置时行为与 M1 完全一致
  （P05 US-2 场景 5 锁定）。
- M2 不建 wasm-gc stub 与 js 适配层（16 属 M5，F9）；各包 target 矩阵按
  宪法 v1.2.0 标注「暂不验证」。
- 夹具策略：M1-P03 夹具库已预留「401/407 挑战（M2 备用）」；M2 新增夹具
  仅 mini CONNECT 代理（P02 内自建，`@socket` 裸 TCP 形态，复用面 P02/P05），
  不再单列测试基建包（M1-P03 地基已备）。

## 5. 每包如何走 speckit

1. 以 `Pxx-*.md` 的「功能描述（speckit 输入种子）」作为 `/speckit-specify`
   的特性描述输入（可整段粘贴，或指明文件路径让 specify 读取全文）。
2. `clarify` 优先消化该包「澄清问题种子」小节，答案回写 spec。
3. `plan` 必须对照宪法（`.specify/memory/constitution.md`）自查，尤其：
   非侵入与上游人工批准（原则 I，P07 全包适用）、性能数据要求（II，P02/
   P06）、OkHttp 语义对齐与有意差异记录（III，P04/P05）、测试先行与可控
   服务端（IV，全包）、target 矩阵（V）、`.mbti` diff 审视（VI）、中文（VII）。
4. 建议特性 slug（分支/规格目录名）：`m2-p01-request-bodies`、
   `m2-p02-proxy-dns`、`m2-p03-interceptors`、`m2-p04-cookies`、
   `m2-p05-auth`、`m2-p06-recipes-gate`、`m2-p07-upstream-prs`。
5. 包间衔接：下游包的 spec 应引用上游包已冻结的 `.mbti` 接口；上游接口
   变更时，下游未开工的包只需改 roadmap 引用，已开工的包走 spec 变更流程。
6. P07 不走常规 implement：其「实现」在上游本地副本，moonhttp 侧仅材料
   与流程；spec 验收以 US-4 合规判据为主。

## 6. 前置条件（首个包动工前的一次性事项）

- M1 全部工作包（P01–P10）交付完成——P03 拦截器链与 P02 代理依赖 M1 的
  接缝、池与夹具地基（当前 M1 处于 P01 已交付、P02–P10 在途状态；
  M2 包可先行 specify/clarify，implement 需等对应 M1 前置落地）。
- `moon.mod` 依赖面变化预申报：P01 引入 `@json` 依赖（宪法 VI 依赖面
  最小化决策，plan 阶段定版本）。
- P07 启动前：与项目所有者确认上游 PR 的批准流程形式（P07 C1）。

## 7. M2 完成的整体判定

P01–P06 全部包级验收判据通过，且第 1 节四条交付判据逐项满足（recipes
全套、syscall 达标实验分支口径、F1–F6 状态更新、≥20× 不回归）；
P07 材料齐备并按批准流程处置（提交或记录搁置理由）。宪法质量门
（v1.2.0：native/wasm 双绿、`moon info && moon fmt` 干净、`.mbti` diff
已审视、性能改动附基准数据；js/wasm-gc 暂不验证）逐项核对通过。
