# P03 双层拦截器链（Interceptor/Chain/peek_body，M1 管线链化迁移）

> 里程碑：M2 完整门面 ｜ 前置依赖：M1-P05（exchange 接缝）、M1-P06（重定向）、
> M1-P07（stale-retry）｜ 人力估计：~4 人日
> 来源：`proj-init-docs/okhttp-on-async-http/04-interceptors/README.md` §1–§8；
> 回补 M1 欠账 **F1**（公开双层拦截器 API）
> 侵入性：非侵入 ｜ 建议特性 slug：`m2-p03-interceptors`

## 功能描述（speckit 输入种子）

把 M1 的内部执行管线升级为 OkHttp 同构的**双层拦截器链**并公开 API：
`Interceptor`（函数字段结构，规避 async trait 限制）与 `Chain::proceed`
（递归游标）；`HttpClient::add_interceptor`/`add_network_interceptor` 注册。
M1 已交付的重定向循环（P06）、stale-retry（P07）与自动头逻辑**迁移为链上
标准层**（RetryAndFollowUp/Bridge），迁移必须行为等价——M1 全部测试作为
回归基线。同时交付 `peek_body(max)`（stream tee 到内存，`@io.pipe` 后台拷贝）、
网络侧 `Chain::connection`（暴露租约的 Address/TLS 元信息）、per-call 超时
覆盖挂点。链序固定（宪法技术约束）：
`[应用拦截器] → RetryAndFollowUp → Bridge → Connect → [网络拦截器] → CallServer`；
Cache 层挂点预留（M4 插入，不破坏公开面）。

## 范围

包含：

- `Interceptor`/`Chain` 类型与递归执行器：短路（不调 proceed）、多次 proceed
  （应用层重试）、请求/响应改写。
- **M1 管线链化迁移**：P06 重定向循环与 P07 stale-retry 判定迁入
  RetryAndFollowUp 层；P02/P05 的自动头（Content-Length/Content-Type 等）
  归入 Bridge 层；迁移以 M1 全部测试零断言修改通过为等价判据。
- `peek_body(max)`：对 stream Response tee 一份到内存（`@io.pipe` + 后台拷贝），
  原流无损供终端消费。
- `Chain::connection`：应用侧恒 None；网络侧暴露 Lease 元信息（Address、
  代理形态；peer 证书读取留 M3/07）。
- `Chain.timeouts`：per-call 超时覆盖挂点（与 M1-P08 per-call 配置的关系见 C4）。
- 官方 recipes 三个示例的库内实现材料：日志拦截器、请求体 gzip 拦截器、
  响应头改写（示例成文在 M2-P06 收口）。

非目标（显式排除）：

- Cache 层（M4/05；仅预留挂点与短路语义验证桩）；
- 401/407 认证 follow-up 行（M2-P05 在 RetryAndFollowUp 决策表回补）；
- Bridge 层 Cookie 注入（M2-P04 接线；本包只留挂点）；
- Accept-Encoding 加宽 br/zstd（L9，M3；Bridge 保持底座内建 gzip 协商不动）；
- 网络拦截器的 js 多次执行语义（js 后端退化为应用层同层，文档标注）。

## 用户故事种子

### US-1 链序与执行语义矩阵（P1）

作为使用者，我注册应用/网络拦截器后，其执行次数与顺序符合 OkHttp 语义。

**独立测试**：P03 夹具 + 顺序记录器；不依赖 P04/P05。

**验收场景**：

1. Given 应用×2 + 网络×1 拦截器，When 单次请求，Then 进出栈顺序为
   应用→内建层→网络的嵌套序（记录器断言）。
2. Given 短路拦截器（应用侧不调 proceed 直接返回伪造 Response），When 请求，
   Then 不达网络层、连接零租借（夹具连接计数为 0）。
3. Given 3 跳重定向脚本，When 请求，Then 应用拦截器执行 1 次、网络拦截器
   执行 3 次（看到中间响应）。
4. Given 缓存命中式短路（桩层模拟 M4 Cache 行为），When 请求，Then 应用侧
   执行 1 次、网络侧 0 次（OkHttp「应用拦截器缓存命中也执行」语义）。

### US-2 改写与多次 proceed（P1）

**验收场景**：

1. Given 拦截器改写请求头后 proceed，Then 服务端收到改写后头。
2. Given 拦截器改写响应头（网络侧），Then 调用方看到改写后头。
3. Given 应用拦截器对同一请求 proceed 两次（模拟重试），Then 两次请求均达
   服务端、最终返回第二次响应、连接租约每 proceed 一次消耗一次（无泄漏，
   池计数守恒）。

### US-3 peek_body（P2）

**验收场景**：

1. Given 流式大 body 响应，When 拦截器 `peek_body(1024)` 后原样 proceed 返回，
   Then 终端消费完整 body 无损、peek 内容为前 1024 字节。
2. Given body 小于 max，Then peek 返回全量且截断语义正确。

### US-4 M1 行为等价回归（P1）

作为 M1 交付的守护者，链化迁移后 M1 全部测试（P02–P10 交付的场景）零断言
修改通过。

**验收场景**：

1. Given M1 测试套件原样运行，Then 全绿（重定向/stale-retry/超时/Dispatcher/
   取消/池行为逐项不回归）。
2. Given M1-P10 基准场景复跑，Then ≥20× 门禁不回归（宪法 II）。

### US-5 Connection 元信息（P3）

**验收场景**：

1. Given 网络拦截器读取 `Chain::connection`，Then 拿到当前租约 Address
   （scheme/host/port/proxy 形态）；应用侧读取恒 None。

## 边界用例

- 零拦截器注册：直通路径与 M1 管线行为完全一致（空链退化）；
- 拦截器抛错/取消传播：`CallCancelled` 穿透链层、租约毒化路径不受链化影响；
- 网络拦截器消费了中间响应 body 未归还（skip 语义必须保住，连接归池判定
  不被链层破坏——02 §3.4 的 skip 责任仍在 RetryAndFollowUp）；
- proceed 后再次修改同一 Chain 状态的幂等性；
- 拦截器内发起嵌套请求（同 Client）——文档声明死锁风险由使用者自负
  （okhttp 同口径）。

## 需求种子

- **FR-001** 链序 MUST 固定为 `[应用]→RetryAndFollowUp→Bridge→Connect→
  [网络]→CallServer`（Cache 挂点 M4 插入）；顺序不得因注册先后变化。
- **FR-002** 应用拦截器 MUST 每调用执行一次（含短路/缓存命中）；网络拦截器
  MUST 对每次网络交换执行（含重定向中间响应）。
- **FR-003** M1 管线迁移 MUST 行为等价：M1 全部测试零断言修改通过。
- **FR-004** 库内各层对 Response body MUST 零拷贝透传（惰性红线：除
  Cache/peek_body 外任何层不得缓冲）。
- **FR-005** `peek_body` MUST 不消耗原流（tee 语义）。
- **FR-006** per-call 超时覆盖挂点 MUST 与 M1-P08 的超时接线协调（clarify C4
  定优先级）。

## 关键设计要点

- `Interceptor` 为函数字段结构（`intercept : async (Chain, Request) -> Response`），
  规避 async trait 方法限制（原报告 §3.1）。
- `Chain` 持 `index` 游标 + `request` + `connection : Lease?` + `mut timeouts`；
  proceed 递归进下一层，末位 CallServer 终端。
- 迁移策略：先建链骨架把 M1 管线原样挂上（零行为变化），再逐层公开——
  每步以 M1 测试回归护航（红-绿-重构，宪法 IV）。
- 折叠头缓存（M1 L3）随 Call 保留，Bridge 层消费同一实例（重放零折叠不回退）。
- 网络侧 Lease 证书挂点预留（`get_peer_certificate` 在 Connect 层抓取，
  M3/07 启用）。

## 侵入性与宪法合规

- **非侵入**：链是 L1 内部结构；底座零改动（04 §4）。
- 宪法 III：链序/执行语义与 OkHttp RealCall 的映射表在 spec 显式记录；
  js 后端网络拦截器退化为应用层同层的差异显式记录。
- 宪法 II：每层一次函数调用 + struct 透传（~十 ns 级）；US-4 锁定 M1 性能
  基线不回归。
- 宪法 IV：先迁移后公开，每步测试先行。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一路径 |
| js | ✅（降级） | fetch 无 Connection/网络层概念：网络拦截器退化为与应用拦截器同层（不执行多次——重定向由浏览器处理）；peek_body 可用；文档标注 |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

- 链长 ~6 时每层一次函数调用，开销 ~十 ns 级，可忽略。
- **惰性 Response 是性能红线**：任何层误缓冲 body 都会毁掉流式语义与内存
  上界——US 边界用例与 code review 重点核对（FR-004）。
- peek_body 仅在显式调用时产生 tee 拷贝。

## 测试方案

- 顺序记录器注入（US-1）；池计数 + 连接计数断言短路/租约语义。
- M1 全量测试回归（US-4，native+wasm 双绿）+ P06 门禁复跑基准（≥20×）。
- peek_body 大 body 截断与原流无损（捕获对端）。
- 惰性红线：流式大 body 穿链后 RSS 无中间全量缓冲（native 观测）。

## 澄清问题种子（clarify 输入）

- **C1** Cache 挂点的预留形态（层位常量 vs 显式空层；保证 M4 插入不破坏
  `.mbti` 公开面）。
- **C2** Bridge 层自动头职责清单（从 M1-P02/P05 迁移哪些头；Accept-Encoding
  保持底座内建的边界）。
- **C3** 拦截器异常/取消的错误分类与租约清理责任归属。
- **C4** `Chain.timeouts` 覆盖与 M1-P08 per-call 超时的优先级与生效范围
  （okhttp `withConnectTimeout` 同款语义的映射记录）。
- **C5** `Chain::connection` 暴露的元信息面（M2 无 TLS 夹具，证书字段留 M3
  的接口占位形态）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）；M1 全量回归零断言
   修改通过。
2. 链序/语义矩阵与 OkHttp 映射表写入 spec（宪法 III）。
3. F1 回补完成可宣告（M1 明细状态更新就绪）。
4. `moon info && moon fmt` 干净；`.mbti` diff 已审视（Interceptor/Chain/
   add_interceptor/add_network_interceptor/peek_body 公开面冻结）。

## 参考

- `04-interceptors/README.md` §3.1–§3.4（类型/链序/惰性交互/recipes）、
  §4（侵入性）、§5–§8。
- M1 欠账 F1；M1 差异 D1（exchange 接缝）；M1-P05/P06/P07（迁移源）。
- 下游引用方：M2-P04（Bridge Cookie 接线）、M2-P05（401/407 决策表行）、
  M4/05（Cache 层插入）。
