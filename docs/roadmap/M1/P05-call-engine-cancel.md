# P05 Call 执行骨架与取消（含 L3 重放零折叠）

> 里程碑：M1 性能核心 ｜ 前置依赖：P01、P02、P04（测试用 P03）｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/01-calls/README.md` §3.5/§6/§8
> 侵入性：非侵入 ｜ 建议特性 slug：`m1-p05-call-engine`

## 功能描述（speckit 输入种子）

交付 moonhttp 的 **Call 执行骨架**：`HttpClient` 门面（持有连接池）与 `Call`
（一次待执行请求的句柄）。`execute` 在当前协程内完成**单次 exchange** 的内部
直连管线：池租借 →（L3：折叠头每 call 一次、缓存在 Call 上）→ `client.request`
发送（定长/chunked 由 P02 转换层决定）→ 写 body → `end_request` 收响应头 →
构建 `Response`（ResponseBody 挂在租约上）→ 按析构契约归池/毒化。
**cancel** 三通道：标记（后续直接终止）/ 子任务组关闭（runtime 水平触发取消，
读写中的协程立即失败）/ 连接毒化（被取消连接不回池）。
管线预留 **exchange 接缝**：M2 的双层拦截器链与 P06/P07 的 follow-up/retry 循环
都插在同一接缝上（README 差异 D1/D2：拦截器与 enqueue 不在本包）。

## 范围

包含：

- `HttpClient` 门面：持有 `ConnectionPool`（及为 P08/P09 预留的配置位）；
  构造 API（直连形态）。
- `Call`：`request`/`client`/`cancelled` 标记；**一次性语义**（重复 execute 报错，
  对齐 OkHttp「Call 不可重复执行」）；`is_cancelled`。
- `Call::execute(request) -> Response raise`：单次 exchange 管线（内部函数
  `exchange(request, lease)` 为接缝，M2 拦截器链与 P06 循环的插入点）。
- 取消：`Call::cancel()`；`CallCancelled` 显式错误变体（宪法 III：区别于网络
  错误，对齐 OkHttp `IOException("canceled")` 的判别用法——映射在 spec 记录）；
  执行体包在可独立取消的子 TaskGroup 中，Call 持句柄。
- L3 落地：折叠头 Map（P02 转换层产物）缓存在 Call 上，重放复用同一实例
  （README 差异 D4 收敛口径：@http 内部逐段 blit 不可避免）。
- 归池/毒化执行侧闭环：响应体完整消费→release 回池；未读完即弃→
  `skip_response_body` 尝试后回池或失败毒化；`Connection: close` 响应头→
  读完即 close（消费 P04 判定接口）；取消/异常→毒化。
- 1xx 信息响应：透传 @http 既有行为（自动跳过并回调，`client.mbt:232-253`），
  spec 记录语义（101 透传留给 M5/12）。

非目标（显式排除）：

- 拦截器链与 Bridge/Cache 层（M2 04 / M4 05；README 差异 D1）；
- `enqueue` 与 Dispatcher（P09；README 差异 D2）；
- follow-up 循环/重定向/重试（P06/P07 在接缝上包裹——本包 execute 只跑单轮，
  P06 落地后循环由其引入）；
- 超时接线（P08 包裹本管线）；
- WebSocket 门面（M5）。

## 用户故事种子

### US-1 execute 单次请求与连接复用（P1）

作为使用者，我用 `HttpClient` 发起 GET/POST（Bytes/Stream 体），得到完整
`Response`（code/headers/body）；连续请求复用池化连接。

**独立测试**：P03 脚本化服务端；不依赖 P06/P07/P08/P09。

**验收场景**：

1. Given echo 夹具，When execute 带 body 的 POST，Then code/headers/body 正确、
   body 内容回显一致。
2. Given 同一 HttpClient 连续 3 次 execute 同 Address，Then 仅第 1 次新建连接
   （夹具侧连接计数 / 池计数断言）。
3. Given `Connection: close` 响应，When 响应体读完后再次 execute，
   Then 新建连接（旧连接未回池）。
4. Given 未知长度 Stream 体，When execute，Then chunked 发送成功（夹具接收校验）。

### US-2 Call 一次性语义（P2）

作为使用者，同一 Call 二次 execute 得到明确错误（`IllegalState` 类），
而非未定义行为。

**验收场景**：

1. Given 已完成的 Call，When 再次 execute，Then raise 状态错误（类型可判别）。

### US-3 cancel 三阶段（P1）

作为使用者，我在任意时点 `cancel()`：发出前、发送中（写 body）、读响应体中；
调用以 `CallCancelled` 终止，被取消连接不回池。

**验收场景**：

1. Given 尚未 execute 的 Call 已 cancel，When execute，Then 立即 raise
   `CallCancelled`、无网络动作。
2. Given P03 慢速接收对端 + 大 body 写入中，When cancel，Then 写入路径以
   `CallCancelled`（或其包装）失败、池内该连接被毒化关闭。
3. Given 慢速滴流 body 读取中，When cancel，Then 读路径失败、连接毒化。
4. When cancel 后 `is_cancelled`，Then true；重复 cancel 幂等无错。

### US-4 重放零折叠（L3，P2）

作为重定向/重试路径的下游（P06/P07），Call 上的折叠头在多次重放间复用，
不重复执行 HeadersV→Map 折叠。

**验收场景**：

1. Given 带多条头的 Request，When 同一 Call 内部强制重放 N 次（桩接缝模拟），
   Then 折叠函数仅执行 1 次（计数断言）、N 次线上字节逐字节相同（P03 捕获对端）。

### US-5 响应体生命周期闭环（P1）

作为使用者，Response 的消费方式决定连接去向：读到底→回池；未读完丢弃→
尝试 skip 后回池，失败则毒化；异常→毒化。

**验收场景**：

1. Given 流式 body 读到最后一块，Then 连接回池（下次 execute 复用）。
2. Given body 读一半即弃，Then 连接被 skip 清理回池（夹具下个请求读到干净流）。
3. Given skip 失败（P03 注入残数据后断连），Then 连接毒化关闭、池计数守恒。

## 边界用例

- execute 中抛非取消错误（连接被 RST）→ 错误透传、连接毒化（重试判定归 P07，
  本包只保证不回池）；
- 1xx 信息响应后再 200（@http 自动跳过）；空 body 响应（Content-Length: 0）；
- 同一 HttpClient 并发多个 Call（各自租借不同连接）互不干扰（池并发前提）；
- cancel 与 release 竞争（cancel 恰在 body 读完后到达——不 double-close）。

## 需求种子

- **FR-001** Call MUST 一次性（二次执行显式报错）。
- **FR-002** cancel MUST 三通道生效：标记终止 / 在途协程取消 / 连接毒化不回池。
- **FR-003** 取消 MUST 以显式 `CallCancelled` 变体暴露（区别于网络错误）。
- **FR-004** 折叠头 MUST 每 call 一次、重放复用（L3）。
- **FR-005** 响应体析构 MUST 遵守 P02 回调契约：完整消费/显式 drop/未读完即弃
  三类事件映射到 回池/回池/回池或毒化。
- **FR-006** exchange 接缝 MUST 显式（内部函数边界），供 M2/P06/P07 插入。
- **FR-007** `Connection: close` 响应 MUST 读完 body 后关闭不回池。

## 关键设计要点

- 取消底座：runtime 取消为水平触发（协程持久标记，后续 async 操作立即失败），
  是 cancel 的天然底座（01 §2 表）；执行体包入可取消子 TaskGroup，Call 持句柄。
- 管线时序（单轮）：acquire → 折叠（缓存）→ `client.request(meth, path,
  extra_headers~)` → body 写（Bytes 分 16–64KB 块）→ `client.end_request` →
  Response 构建 → body 消费 → release。read/write 的按操作超时包裹点由 P08
  在同一时序上叠加。
- 归池前提：`end_request` 已返回且 body 完整消费（宪法「技术约束」与 03 §3.2）；
  连接状态机要求 clean state（`client.mbt:351-355` guard 同理）。
- 发送路径对象数目标：连接已建时 ≈ 2 个对象（头块引用 + body 引用，01 §6）。

## 侵入性与宪法合规

- 非侵入：`request/write/end_request/skip_response_body/close` 全公开 API。
- 宪法 III：取消/错误分类的 OkHttp 映射表在 spec 显式记录（`CallCancelled`
  vs `IOException("canceled")`）。
- 宪法 II：L3 属性能杠杆，收益（重放路径免重复折叠）在 P10 的重定向/重试场景
  基准中体现；US-4 提供机制级断言。
- 宪法 VI：门面字段最小化（仅 pool + 预留位），builder 全量 API 随 P08。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一路径 |
| js | ⚠️ | fetch 路径：execute 直通（无池语义），cancel 经 AbortController（@http js 后端已接）；连接毒化/归池语义不适用 |
| wasm-gc | ❌ | 上游 runtime 缺口 |

## 性能影响

- L3：重放路径零折叠（机制断言 + P10 量化）。
- 管线自身不加分配放大：折叠缓存后，热路径新增对象 ≈ Lease + Response 壳。

## 测试方案

- US-1/3/5 全部基于 P03 夹具（echo/慢速/残数据/连接计数）；native+wasm 双绿。
- US-4 用桩接缝 + 捕获对端做计数与字节级断言。
- js：`moon check --target js` + （可行时）node 冒烟：execute+cancel 直通路径。

## 澄清问题种子

- **C1** 子 TaskGroup 取消句柄的具体 API 形状（@async TaskGroup/Semaphore 公开面，
  0.22.x 核实）与 Call 的所有权（Call 持句柄的生命周期边界）。
- **C2** 「未读完即弃」的默认策略：显式 drop API 形状 vs Drop trait 语义
  （MoonBit 析构时机对回池时机的影响——若语言层析构不可靠，则强制显式 API，
  spec 记录）。
- **C3** 1xx 回调是否在 M1 暴露给用户（@http 已有 `on_informational_response`；
  暴露面最小化 vs 透传）。
- **C4** execute 的并发语义文档：同 HttpClient 多 Call 并发 = 池并发租借
  （无 Dispatcher 闸门，P09 之前不设限）——是否在 API 文档显式声明。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. 取消三阶段 + 毒化（连接不回池）有池计数侧断言。
3. `moon info && moon fmt` 干净；`.mbti` 冻结 HttpClient/Call 公开面（execute/
   cancel/is_cancelled；无 enqueue）。
4. OkHttp 映射表（Call 一次性、取消错误分类）写入 spec。

## 参考

- `01-calls/README.md` §3.5（Call/取消三通道）、§6（头块缓存与分配目标）、§8。
- `03-connection-pool/README.md` §3.2（归池前提）、§3.4（毒化表）。
- 下游引用方：P06（循环包裹接缝）、P07（recover 插入）、P08（超时包裹）、
  P09（enqueue+闸门）、M2 04（拦截器链接缝）。
