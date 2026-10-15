# P06 recipes 收口与 M2 门禁（OkHttp recipes 全套 + 基线不回归 + 上传 syscall 度量）

> 里程碑：M2 完整门面 ｜ 前置依赖：M2-P01–P05 ｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/README.md` §4（M2 交付判据）、
> `14-performance/README.md` §5/§6、`04-interceptors/README.md` §3.4
> 侵入性：非侵入（syscall 度量的实验分支见 D3 口径）｜ 建议特性 slug：
> `m2-p06-recipes-gate`

## 功能描述（speckit 输入种子）

M2 收口包：把 M2 各包能力编织成 **OkHttp recipes 全套可运行示例集**并跑通，
同时建立 **M2 性能门禁**。recipes 面覆盖：日志拦截器、请求体 gzip 压缩、
响应头改写（04 §3.4 三例）；POST String/流式/文件、FormBody、Multipart
上传、上传/下载进度（09 recipes）；CookieJar 内存与持久化（11 recipes）；
Basic 认证与 401 follow-up（08 recipes）。门禁面：M1 基线（池化 ≥20×）不
回归；DNS 缓存收益数据（新建连接场景）；上传 syscall 度量——主分支 send_buf
仍 1KB（上游 I1 未合并），达标数据以**本地实验分支**（pull 上游副本 + 16KB
补丁，宪法技术约束允许的联调形态）实测并归档报告，作为 I1 PR 的证据材料。

## 范围

包含：

- recipes 示例集（宿主位置 clarify C1：`examples/` 目录 vs 库 README 内嵌），
  每个示例可编译、可在 loopback 夹具上跑通并断言结果。
- M2 门禁执行：M1-P10 基准场景复跑（≥20× 不回归）+ DNS 缓存场景数据
  （池冷启动/驱逐频繁场景的建连延迟对比）+ 401/407/重定向组合场景冒烟。
- 上传 syscall 度量：实验分支搭建（上游本地副本 + I1 补丁 + 本地包引用联调，
  不进主分支）、100MB 上传 syscall 计数、报告归档（P07 PR 材料输入）。
- M2 完成判定清单执行（README 第 6 节）。

非目标（显式排除）：

- 基准服务端的高吞吐优化（沿用 P10/M1 方法学，不新增）；
- 真实网络点位测量（loopback 口径与 round1–3 可比，宪法 IV）；
- I1/I2/I5 的实际提交（M2-P07；且须人工批准）；
- wasm-gc/js 的门禁恢复（M5/F9）。

## 用户故事种子

### US-1 recipes 全套可运行（P1）

作为使用者与交付判据验收者，我按示例清单逐个运行，全部行为符合对应
OkHttp recipe 的预期。

**独立测试**：每示例配 loopback 夹具脚本与自证断言。

**验收场景**：

1. 拦截器三例：日志拦截器输出请求行/耗时（敏感头默认掩码不出现）、请求体
   gzip 后服务端解压回显一致、响应头改写生效。
2. 请求体家族：POST String 定长、FormBody 编码回显、Multipart 文件上传
   逐字节校验、进度回调计数正确。
3. Cookie：内存 Jar 跨请求携带、FileCookieJar 重启后仍携带。
4. 认证：401 follow-up 自动重发成功；407 隧道场景（mini 代理夹具）闭环。

### US-2 M2 门禁（P1）

作为性能守护者，M2 交付后 M1 性能基线不回归，且新增杠杆有量化数据。

**验收场景**：

1. Given M1-P10 场景矩阵复跑，Then 池化 ≥20× 保持（round2 口径）。
2. Given DNS 缓存开/关对比（新建连接场景），Then 建连延迟差可测并归档
   （方向性数据，不设硬门槛——getaddrinfo 往返量级背书）。
3. Given 401 重试 × 重定向 × 池复用组合冒烟，Then 全绿（链化后交互面兜底）。

### US-3 上传 syscall 度量（P2，D3 口径）

**验收场景**：

1. Given 实验分支（上游副本 + I1 16KB 补丁），When 上传 100MB，Then syscall
   计数 ≤ 每 16KB 一次的量级（14 §5 门槛），与主分支（1KB 现状）对比数据
   一并归档。
2. 实验分支改动不进主分支（git 核验）；报告含复现步骤。

## 边界用例

- recipes 示例间共享夹具端口的隔离（每示例独立端口分配）；
- 门禁机器噪声（多轮取中位数，M1 方法学沿用）；
- 实验分支上游副本版本漂移（钉 0.22.x 对应 commit 记录）。

## 需求种子

- **FR-001** recipes 示例 MUST 每个可独立运行且有自证断言（宪法 IV）。
- **FR-002** M1 基线门禁 MUST 复跑并归档（≥20×）。
- **FR-003** 上传 syscall 度量 MUST 在实验分支完成且报告含主分支对照。
- **FR-004** 示例与门禁输出 MUST 不含敏感头值（默认掩码/合成值）。

## 关键设计要点

- recipes 是 M2 判据「OkHttp recipes 全套可写」的载体：示例即文档（写成
  库 README 的 cookbook 节或 examples，clarify C1）。
- syscall 计数方法（clarify C2）：native 下 strace/procfs 计数或宿主侧探针，
  plan 定并保证两分支同法可比。
- 门禁归档格式沿用 M1-P10 报告形态，追加 M2 节。

## 侵入性与宪法合规

- 非侵入；实验分支的上游改动遵循宪法技术约束（本地副本联调、不进主分支）。
- 宪法 II：性能改动附带基准数据（本包是 M2 的数据归口）。
- 宪法 IV：示例自证断言；全部 loopback。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 门禁与示例主战场（质量门双绿） |
| js | ⚠️ | 示例不跑 js（暂不验证，宪法 v1.2.0）；门禁不涉及 |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

不适用（度量与收口包本身；其产出是性能证据）。

## 测试方案

- recipes 自证断言 + 门禁复跑归档；native+wasm 双绿。
- 实验分支度量仅 native（syscall 概念仅 native/wasm 有意义，wasm 宿主调用
  计数不测）。

## 澄清问题种子（clarify 输入）

- **C1** recipes 宿主位置（examples/ 目录 vs README cookbook 节；对发布面
  的影响）。
- **C2** syscall 计数的具体方法与两分支可比性（strace 可用性/宿主探针）。
- **C3** 门禁执行频率（每合入 vs 每里程碑收口；M1-P10 的既有口径沿用）。
- **C4** DNS 缓存收益场景的口径（池冷启动并发 N 建连 vs 逐个新建）。

## 验收判据（包级 DoD）

1. US-1 recipes 全套运行断言通过（native/wasm 双 target）。
2. US-2 门禁三项数据归档（≥20× / DNS 缓存对比 / 组合冒烟）。
3. US-3 实验分支度量报告归档且主分支零污染（git 核验）。
4. `moon info && moon fmt` 干净（示例包入库时）。

## 参考

- `README.md` §4（M2 判据）、`14-performance/README.md` §3.1/§5/§6、
  `04-interceptors/README.md` §3.4、`09-request-bodies/README.md` §1。
- M1-P10（基线方法学）、M2-P01–P05（示例材料）。
- 下游引用方：M2-P07（I1 PR 证据）、README 第 6 节（M2 完成判定）。
