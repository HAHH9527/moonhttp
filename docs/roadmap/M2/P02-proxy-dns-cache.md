# P02 代理支持与 DNS 缓存（ProxyConfig/CONNECT 隧道/代理池化/L4 自组缓存）

> 里程碑：M2 完整门面 ｜ 前置依赖：M1-P04（Address/连接池）、M1-P03（夹具）｜ 人力估计：~2 人日
> 来源：`proj-init-docs/okhttp-on-async-http/03-connection-pool/README.md` §3.5/§3.6；
> 回补 M1 欠账 **F2**（代理支持）、**F3**（DNS 缓存）
> 侵入性：非侵入（CONNECT-only；absolute-form 依赖上游 I5，不在本包，见 F14）
> ｜ 建议特性 slug：`m2-p02-proxy-dns`

## 功能描述（speckit 输入种子）

为 moonhttp 补齐连接层的两个 M1 划出项：**代理支持**与 **DNS 缓存**。
代理侧：`ProxyConfig`（Direct / Http{addr, auth?}）进入 `Address` 池键；
到代理的 CONNECT 隧道连接本身池化复用；静态凭据经持久头预置进 CONNECT 请求
（407 挑战驱动的回调式认证在 M2-P05 集成）；http-over-proxy 的 absolute-form
直发**不做**（依赖上游 Host 覆盖 PR·I5，M2 主分支维持 CONNECT-only 降级并
在文档显式标注）。DNS 缓存侧：进程内 `Map[host, (Addr 列表, expiry)]` 自组版
（TTL 取 resolver 返回 min、不可得默认 30s），命中时绕过 `connect_to_host`、
以 250ms 错峰复刻 Happy Eyeballs 竞速（非侵入，L4 杠杆）；上游共享缓存版
（I2 PR）合并前自组版即 M2 终态口径。

## 范围

包含：

- `ProxyConfig`（Direct/Http{addr, auth?}）与 `Address` 扩展：`proxy` 字段
  进池键指纹；同批为 `Address` 加 `trust` 占位字段（默认 SystemRoot，进池键，
  M3/07 落地时生效——M1 速查节既定口径）。
- 代理连接建立：经代理 `Client` 的 CONNECT 隧道（底座 `proxy~` 参数公开面）；
  隧道连接包装为目标 Address 的租约。
- 代理 Client 池化：到代理的连接独立成池（键含代理 addr），复用隧道外壳。
- 静态代理凭据：`ProxyConfig::Http.auth` 配置时，凭据头预置进 CONNECT 请求
  （底座持久头机制，03 §3.3 证据）。
- 系统代理读取（native，纯上层）：`http_proxy`/`https_proxy`/`no_proxy`
  环境变量（可选项，clarify C2 定去留）。
- L4 DNS 缓存自组版：缓存结构、TTL、命中竞速路径、未命中回填、错误分类
  自包装（绕过 `connect_to_host` 后失去的内部错误分类需补齐）。
- 本地代理测试夹具：`@socket` 裸 TCP mini 代理（读 CONNECT、可脚本化回
  407/200、隧道双向泵）——P03 夹具库扩展。

非目标（显式排除）：

- **http-over-proxy absolute-form**（`GET http://origin/path` 直发）：依赖
  上游 Host 覆盖 PR·I5（~5 行，**须人工批准**），本包维持 CONNECT-only 降级；
  回补欠账 **F14**；
- DNS 缓存的上游共享版切换（I2 PR 材料在 M2-P07；合并后回补 **F15**）；
- Route 级选择器（每 IP 独立池化，原报告明示不建议）；
- Windows 注册表/系统设置代理（原报告明示不在 M 范围）；
- 代理的 407 回调式 Authenticator 集成（M2-P05 承接，本包只留静态凭据路径）。

## 用户故事种子

### US-1 CONNECT 隧道代理（P1）

作为使用者，我配置 `ProxyConfig::Http` 后发 http/https 请求；连接经代理
CONNECT 隧道建立。

**独立测试**：本地 mini 代理夹具；不依赖本里程碑其他包。

**验收场景**：

1. Given mini 代理夹具（CONNECT 回 200 后双向泵），When https 目标请求，
   Then 夹具收到 `CONNECT host:port` 行、随后透传的请求在目标 echo 服务端
   完整到达、响应正确返回。
2. Given 同一代理 + 同一目标，When 连续两次请求，Then 第二次复用既有隧道
   （夹具 CONNECT 计数 == 1）。
3. Given 两个不同代理配置指向同一目标，When 各自请求，Then 池内为两条独立
   租约（`proxy` 进池键断言）。

### US-2 静态代理凭据（P2）

作为使用者，我在 `ProxyConfig::Http` 配置静态凭据；CONNECT 请求自动携带
`Proxy-Authorization`。

**验收场景**：

1. Given 代理夹具校验 CONNECT 头，When 携带 auth 配置建隧道，Then CONNECT 行
   含正确 `Proxy-Authorization: Basic ...`。
2. Given 凭据错误（夹具先回 407），When 建隧道，Then 得到可判别的代理错误
   （挑战驱动的重试闭环在 M2-P05 验收）。

### US-3 DNS 缓存（P1）

作为使用者，我在高频新建连接场景受益于 DNS 缓存：同一 host 的重复建连不再
全量解析。

**验收场景**：

1. Given 缓存冷启动，When 首次建连，Then 未命中回填（缓存层命中/未命中计数
   断言）。
2. Given TTL 内二次建连，When 建连，Then 缓存命中、走自组竞速路径
   （解析调用计数不增长——以可注入 resolver 断言，见 C1）。
3. Given TTL 过期（测试用短 TTL 注入），When 再建连，Then 重新解析并回填。
4. Given 解析失败（注入失败 resolver），Then 错误分类与直连路径一致
   （错误类型可判别、分类不因缓存路径漂移）。

### US-4 Address 池键完整性（P2）

作为连接池语义的守护者，`proxy`/`trust` 变更必须产生不同池条目，杜绝跨配置
串连接。

**验收场景**：

1. Given 同 host 同 port 但 proxy 不同的两个 Address，When 交替租借，Then
   各自命中各自空闲连接（复用计数互不污染）。
2. Given trust 不同的两个 Address（占位字段），When 交替租借，Then 池条目
   独立（为 M3/07 生效做机制准备）。

## 边界用例

- 代理地址即目标地址（自指）与代理端口占用（建连失败错误透传）；
- CONNECT 响应非 2xx（407/502）的错误分类形态（clarify C4）；
- 缓存到期与建连进行中的竞争（过期瞬间命中→按未命中处理，不返回过期地址）；
- IPv6 字面量 host 与缓存键（剥括号后的规范化形态，对齐 M1-P01）；
- no_proxy 匹配（若 C2 纳入系统代理）后缀语义。

## 需求种子

- **FR-001** `proxy`/`trust` MUST 参与 Address 池键指纹。
- **FR-002** 代理隧道连接 MUST 池化复用；代理 Client 生命周期挂门面。
- **FR-003** 静态凭据 MUST 仅进 CONNECT 请求持久头，不污染目标请求头。
- **FR-004** DNS 缓存 MUST 有 TTL（min TTL 或默认 30s）、命中绕过
  `connect_to_host` 时 MUST 自组 250ms 错峰竞速（语义对齐底座 Happy Eyeballs）。
- **FR-005** 缓存路径的建连错误 MUST 与直连路径同分类（自包装补齐）。
- **FR-006** absolute-form 不实现 MUST 在文档与 spec 显式标注（CONNECT-only
  降级声明，F14 跟踪）。

## 关键设计要点

- 池键扩展：`Address` 增 `proxy : ProxyConfig?` 与 `trust`（占位），derive
  Hash/Eq 进键；存量直连路径零行为变化（proxy=None 时与 M1 完全同路径）。
- 代理 Client 池：到代理的 Client 按（proxy addr）键入池；隧道复用 = 复用
  到代理的连接（底座 CONNECT 隧道建立后的 Client 即目标会话外壳）。
- DNS 缓存层注入点：resolver 抽象（默认 `@socket.Addr::resolve`），测试注入
  stub——解决 getaddrinfo 不可观测问题（C1）。
- 竞速复刻：缓存 Addr 列表 + `@async.any` + `Tcp::connect(addr)` + 250ms
  错峰（`happy_eyeball.mbt:30-106` 同款语义，~40 行，手法对齐、代码自建）。
- trust 占位字段本包仅进键不生效（验证面 M3/07）——避免 M3 再动池键造成
  二次接口破坏。

## 侵入性与宪法合规

- 全部**非侵入**：CONNECT 经底座 `proxy~` 公开参数；DNS 缓存经
  `Addr::resolve`/`Tcp::connect` 公开 API 自组。
- 宪法 I：I5（Host 覆盖）/I2（上游共享缓存）仅以 PR 材料形态存在于 M2-P07，
  提交须人工批准；主分支合并前维持降级口径。
- 宪法 II：L4 杠杆收益（新建连接省 getaddrinfo 往返 ~100µs+）在 M2-P06
  门禁出数据。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native | ✅ | 全功能（含 CONNECT 代理、DNS 缓存、环境变量系统代理） |
| wasm | ✅ | socket = moonrun 宿主直通；池/缓存逻辑同源；环境变量读取按宿主能力在 plan 定 |
| js | ⭕ 无意义 | fetch 连接由浏览器管理；代理/DNS 缓存层退化为直通（文档标注） |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

- DNS 缓存：高频新建连接场景省 getaddrinfo（线程池往返 ~100µs+）；池化后
  DNS 次数本已与新建连接同阶，本杠杆收益集中在池冷启动与驱逐频繁场景。
- 缓存自身：每 URL 一次 Map 查找（µs 级以下）。
- 代理：隧道复用后代理路径请求成本与直连同阶。

## 测试方案

- US-1/2 基于 mini 代理夹具（`@socket` 裸 TCP，P03 夹具库扩展）：CONNECT 行
  断言、隧道透传端到端、复用计数。
- US-3 基于注入式 resolver 单测 + loopback 集成（命中/未命中/TTL/错误分类）。
- US-4 池键指纹断言（M1-P04 计数手法复用）。
- 全部网络行为测试基于本地可控服务端（宪法 IV）；native+wasm 双绿。

## 澄清问题种子（clarify 输入）

- **C1** DNS 缓存可观测方案：resolver 抽象注入（推荐）vs 缓存层计数器暴露
  （影响 `.mbti` 公开面）。
- **C2** 系统代理环境变量是否纳入本包（含大小写变体、no_proxy 语义）；wasm
  宿主下读取能力。
- **C3** 代理 Client 的超时/池参数派生规则（与目标 Address 的 connect timeout
  关系）。
- **C4** CONNECT 非 2xx 响应的错误分类形态（复用底座 ProxyError vs 自定
  变体）。
- **C5** trust 占位字段的默认值与 spec 记录口径（M3 生效前的行为承诺）。

## 验收判据（包级 DoD）

1. US-1–US-4 验收场景测试全绿（native/wasm 双 target）。
2. CONNECT-only 降级声明与 F14 引用写入库文档与 spec。
3. 池键扩展后 M1-P04 全部既有测试零断言修改通过（直连路径行为等价）。
4. F2/F3 回补完成可宣告（M1 明细状态更新就绪；F3 的上游切换部分转 F15）。
5. `moon info && moon fmt` 干净；`.mbti` diff 已审视（Address 字段扩展为
   破坏性变化，spec 与 changelog 显式记录）。

## 参考

- `03-connection-pool/README.md` §3.1（Address 键）、§3.5（DNS 缓存）、
  §3.6（代理形态）、§5、§8。
- M1 欠账 F2/F3；M1 差异 D3；M1 速查节（trust 字段随 F2 一并考虑）。
- `14-performance/README.md` §2 L4、§6（M2 落地顺序）。
- 下游引用方：M2-P05（407 场景）、M2-P07（I2/I5 PR 材料）。
