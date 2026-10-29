# Research: 自动重定向 follow-up 循环（M1-P06）

> Phase 0 产物。每条决策按 Decision / Rationale / Alternatives 记录。
> 取证日期 2026-10-27；OkHttp 基准 = tag `parent-5.5.0`（宪法 III），
> 文件 `okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/
> RetryAndFollowUpInterceptor.kt`（下称 RFU）与 `HttpMethod.kt`，
> 行号以本次取证副本为准。

## R1 OkHttp 5.5.0 对拍真值（决策表/上限/one-shot/剥头）

**Decision**: 决策表、上限语义、one-shot 处置、剥头范围全部按以下
源码事实实现（spec 映射表已录）：

1. 跟随分支：`HTTP_PERM_REDIRECT(308), HTTP_TEMP_REDIRECT(307),
   HTTP_MULT_CHOICE(300), HTTP_MOVED_PERM(301), HTTP_MOVED_TEMP(302),
   HTTP_SEE_OTHER(303)`（RFU L228）——**300 属跟随分支**。
2. 方法改写门：`if (HttpMethod.permitsRequestBody(method))`
   （RFU L314；`permitsRequestBody = !(GET || HEAD)`）——GET/HEAD
   全状态码保持，连整个改写块都不进入。
3. 降级判定 `HttpMethod.redirectsToGet(method, code)`（两参版）：
   303 → 除 PROPFIND 外一律改 GET；307/308 → 恒 false（保持）；
   300/301/302 → 除 PROPFIND/QUERY 外一律改 GET。**PUT/DELETE 在
   300/301/302 同样降级**——种子「仅 POST」为过时口径（C2 修正）。
   M1 九标准方法集不含 PROPFIND/QUERY ⇒ M1 规则：非 GET/HEAD 一律
   降级。
4. 降级时移除头：`Transfer-Encoding`/`Content-Length`/`Content-Type`
   （RFU L318-320）。
5. one-shot：`followUp.body?.isOneShot()` ⇒ 原样返回该 3xx 响应
   （RFU L104-109）——moonhttp `Stream`（一次性回调体）为其等价物，
   307/308 + Stream 不跟随 = **对齐**而非差异。
6. 跨 host：`removeHeader("Authorization")` 仅此一头（RFU L326-331，
   注释明言 "drop all authentication headers"）；**无 Cookie 剥除**
   ——OkHttp 的 Cookie 跨域安全由 BridgeInterceptor+CookieJar 按新域
   重算达成。M1 无 Jar ⇒ 剥手设 `Authorization`+`Cookie`（C1 有意
   差异，M2/11-cookies 回改——2026-10-28 review 修复批订正，与
   roadmap P01:36/P02:45 口径对齐）。
7. 跨 host 判定：`!userResponse.request.url.canReuseConnectionFor(url)`
   ——scheme/host/port 相等才可复用连接；与 P06「scheme/host/port
   任一不同即跨 host」一致（实现用 `Address` Eq 判定，见 R4）。
8. 上限：`MAX_FOLLOW_UPS = 20`（RFU L355 私有常量）；检查位置在
   「响应到达 + followUp 已算出」之后、「发送 follow-up」之前
   （L111-116：先 `closeQuietly` 排干，再 `++followUpCount > 20`）。
   ⇒ 至多发出 20 个 follow-up（总请求数 21）；收到第 21 个仍需跟随
   的响应即抛 `ProtocolException("Too many follow-up requests: n")`。
9. Location：`header("Location") ?: return null`、
   `url.resolve(location) ?: return null`（L304-306）——缺失/不可
   解析即不跟随，原响应终态。
10. 超出 P06 范围的分支实况（录给 P07）：401→authenticator（L224）、
    407→proxy authenticator（L216）、408 在默认
    `retryOnConnectionFailure=true` 下**会**重试（L232-255，非种子
    所述「OkHttp 无此默认」——种子口径修正记录于 spec 映射表）、
    503 按 Retry-After（L258-271）、421 连接合并重试（L273-288）。

**Rationale**: 宪法 III 以 5.5.0 为行为规范基准；种子 C1/C2 明示
「spec 阶段对拍确认」，对拍发现两处种子过时口径（C2 降级集合、300
跟随）与一处安全增强默认（C1 剥 Cookie），均按宪法基准或显式差异
处理并回记 spec。

**Alternatives considered**: 按 4.x 行为「仅 POST 降级」——被宪法
III 基准否决（5.5.0 已改）；300 按种子不跟随——同上否决。

## R2 循环落位点与取消接线

**Decision**: 循环放在 `Call::execute` 组内 spawn 的子任务体中：
新增 `exchange_loop()` 替换现 `exchange_once()` 作为 spawn 目标；
每轮循环顶 guard `self.cancelled`（FR-001），轮内取消复用 P05 全部
既有机制（`Task::cancel` 在途失败 → `errdefer poison_release` →
`handle_cancellation`/`WaitedTaskAlreadyCancelled` 映射裸
`CallCancelled`）。`ExchangeOutcome` 两分支结构零变化。

**Rationale**: P05 execute 骨架（http_client.mbt L126-187）已把
「组生命周期/取消映射/终态置位」全部收敛在 spawn 外壳；循环只改
spawn 的任务体，取消语义天然逐轮生效，零新增并发原语。证据：
每轮 guard 对齐 OkHttp `if (call.isCanceled()) throw IOException`
（RFU 循环顶）；mid-round 取消由 task.cancel 覆盖（P05 FR-002b）。

**Alternatives considered**: ①循环放 execute 体内、每轮开新组——
组创建开销 ×20 且终态置位逻辑需重写，否决；②循环放拦截器式独立
结构——M1 无拦截器链（D1），提前抽象违宪 VI（YAGNI），P07/P08/
M2 均在本接缝上包裹即可。

## R3 接缝参数化与 Call 新增内部状态

**Decision**:
- `exchange_once(request : @core.Request)` 参数化（原读
  `self.request`）；`exchange_with_lease(request : @core.Request)`
  同步参数化；单轮语义不变——P05 白盒直调路径以补实参最小适配。
  （round8 Q-B3 记号口径：产物内 `exchange_*(request)` 写法是参数化
  后的目标形态记号；P05 实况为无 request 参的
  `exchange_once(self)`/`exchange_with_lease(self, lease)`、读
  `self.request`（exchange.mbt:78/:91）——实现以 exchange.mbt
  实况签名为准做适配，本记号不回改。）
- Call 新增 3 个 priv 字段（contracts 不涉公开面）：
  `gen : Int32`（当前请求代次，0 = 用户原请求）、
  `folded_gen : Int32`（折叠缓存所属代次）、
  `conn_close_seen : Bool`（本轮响应已见
  `Connection: close` → 租约已 poison 标记）。
  **不设 `lease_addr` 镜像字段**（round3 D-4 订正）：初稿括注
  「Lease 无 addr 访问器」失实——`Lease` 持 `priv addr : Address`
  （client.mbt:134-141，:137 在场），MoonBit priv 同包可读（先例
  exchange.mbt:98 直读 `lease.conn`），租约地址一律经 `lease.addr`
  直读判定；按宪法 VI 删除冗余状态面及其同步不变量负担。
- 折叠缓存代次键化（C4 落地）：`folded_headers(request, gen)`——
  `folded_gen == gen ∧ folded is Some` 时复用同一 Map 实例；否则
  `request.to_http_request().headers` 折叠一次并存
  `{folded, folded_gen, fold_count+1}`。代次不变的重放（P07 场景）
  复用缓存 ⇒ P05 SC-004「同代次 N 次重放折叠恰 1 次」语义保持。
- 换代时机：循环在「决定跟随」后 `self.gen += 1`，下一轮
  `folded_headers` 自然重折叠新请求恰一次。

**Rationale**: exchange.mbt 现状（folded_headers L60-72 读
self.request；exchange_once L78-86 读 self.request 推 Address）是
单请求假设；参数化是最小改动且保住 P05 全部单轮行为。代次键化而非
「仅原请求缓存」（C4 备选）：follow-up 头已改写，复用原请求折叠
产物=正确性错误（FR-010）。

**Alternatives considered**: ①`Call.current_request` 可变字段替代
参数传递——引取自 P05 白盒测试字段语义（request=用户原请求）被破坏
且公开访问器语义模糊，否决；②Map[gen, folded] 全代次缓存——M1 无
回跳代次的消费方（P07 重放同代次），YAGNI 否决，仅保留当前代次
单槽。

## R4 Location 解析、头改写与请求重组

**Decision**:
- Location 读取：`response.headers().get("Location")`（HeadersV::get
  大小写不敏感——P02 契约）。
- 解析：`request.url.resolve(location)`（core mbti L86：
  `HttpUrl::resolve(Self, String) -> Self raise HttpUrlError`）；
  `catch HttpUrlError => 不跟随终态`（FR-008）。非 http(s) scheme
  的绝对引用按 P01 resolve 契约自然拒绝，同归 FR-008 终态。
- 跨 host 判定：`address_of_request(request) != address_of(target)`
  （Address derive Eq；scheme/host/port 三元组语义与 5.5.0
  canReuseConnectionFor 一致——R1 第 7 条）。
- 头改写：`orig.builder()`（HeadersV::builder 防御性复制）→
  跨 host `remove("Authorization")` + `remove("Cookie")` → 降级
  `remove("Content-Length")` + `remove("Content-Type")` +
  `remove("Transfer-Encoding")`（5.5.0 三头全录，存在才移；P02
  转换层自身不注 Transfer-Encoding，但用户手设时 5.5.0 行为是移除
  ——对齐）→ `build()`。
- follow-up 重组：`RequestBuilder::new(target)` → `.method(...)` →
  `.headers(new_headers)` →（保持体时）`.body(request.body 原值)` →
  `.build()`。方法体矩阵边界核证（P02 build 校验）：降级 GET 无体 ✓
  合法；307/308 保持 POST 必有体（原请求矩阵已保证）✓；HEAD 保持
  无体 ✓；`HttpMessageError` 理论不可达（构造合法输入），不可达仍
  以 raise 透传（防御性，不加吞）。

**Rationale**: 全部走 P01/P02 公开面（宪法 I/VI）；`remove` 在
mbti L64 在场；RequestBuilder 五件套在 mbti L138-145 在场，零 core
改动。体原值搬移合法：RequestBody 不可变值（P02 契约），Bytes 体
重放语义由 P05 write_once 路径保证（US-2-1 对端两次字节一致断言）。

**Alternatives considered**: 手搓头容器复制——绕过 builder 校验面，
否决；Location 大小写敏感 get——HTTP 头名大小写不敏感，P02 get 已
处理，无需特判。

## R5 prior 链构建

**Decision**:
- prior 条目构建：`prior_entry(resp, prev) = Response::from_http(
  resp.code(), resp.reason(), resp.headers().to_http_map(),
  resp.cookies(), body=None, prior=prev)`。头经
  `HeadersV::to_http_map`（折叠）→ `from_http` 逐键拆回——P02 设计
  的互逆路径（core codemap「头折叠与重建互逆」），无信息损失。
- 终态响应挂链：同上但 `body=resp.body()`（活体透传，租约语义
  P05 不变）。
- **prior 条目 body=None**（对齐 OkHttp：中间响应体已排干关闭，
  priorResponse 无体可读）；链序：终态.prior = 第 n-1 跳响应，
  逐级回溯达最初 3xx 响应（FR-006 链深 = 实际跳数）。
- 307/308 + Stream 不跟随的终态：同样挂已累积 prior（若已在第 2+
  轮），首轮则 prior=None——「原样返回」语义 + 历史链不丢。

**Rationale**: `Response::from_http` 带 `prior?` 装配位（P02 预留，
mbti L158）、`Response::prior` 访问器在场（L160）——P06 只填充零
core 改动。OkHttp RFU L120 `priorResponse = response` 同构。

**Alternatives considered**: 复用中间响应对象直接串链（body 不置
None）——prior 链条目持活体会让租约语义混乱（多份 body 引用同一
conn），且 OkHttp priorResponse 无体，否决。

## R6 中间响应排干与租约保持

**Decision**:
- 排干：中间响应**不走 bridge 体读路径**（不交付、不触发
  Consumed/Dropped 事件），直接 `lease.conn.skip_response_body()`
  （与 P05 `dispose_skip` 同款上游 API；body_bridge.mbt L102-110
  先例）。skip 失败 → 错误透传（FR-002 毒化半边；毒化由轮级
  `errdefer poison_release()` 统一实现、drain 内不另写 catch——
  处置归属单点，见 data-model 实体 1 注记，round3 D-2；P07 将在
  该错误上做 recover）。
- 同 host 保持（FR-007）：排干后**不 release**，下一轮
  `ensure_lease(next_addr)` 见 `lease is Some ∧ lease.addr == addr`
  直接复用（零归还-重取往返）。
- 跨 host 换租：排干成功后 `release_lease()`（干净连接回池，P04
  契约）→ 下一轮 `ensure_lease` acquire 新地址；skip 失败路径已
  poison，不回池。
- `Connection: close` 中间响应（FR-009）：exchange_with_lease 既有
  token 解析命中即 `lease.poison()`（exchange.mbt L112-124）——新增
  `conn_close_seen = true` 同步置位；循环 advance 时见该标记即
  `release_lease()`（poisoned release = 关闭不回池）。标记在
  `ensure_lease` 取新租时复位（I-7）。
- 上限抛出前（第 21 个仍需跟随的响应）：排干照常 →
  `release_lease()`（干净回池，对齐 OkHttp L111 closeQuietly 后才
  检查计数——连接可复用）→ raise `TooManyFollowUps`（先 release
  后 raise，errdefer 随后 no-op——连接保持干净回池；round3 D-2）。

**Rationale**: skip 直调是 @http 公开面（R2/P05 已核证）；bridge
体不交付则无事件义务（P02 契约：事件触发权在 dispose/read 边界，
不交付即不触发）；租约处置单点仍是 `Call.lease`（I-3 时序支点不变，
body_bridge.mbt L10-11 所有权注释）。OkHttp 同 host 多跳本就复用
同一 exchange/连接（report 02 §6），moonhttp 以 lease.addr 同包直读判定
等价实现。

**Alternatives considered**: ①中间响应也走完整 ResponseBody +
dispose——多余一次桥接装配且 Consumed→release 会破坏同 host 保持，
否决；②跨 host 直接 poison 旧租——连接是干净的，poison 浪费可用
连接且偏离 P04「未毒化回池」谓词，否决。

## R7 P03 夹具能力核证（零扩展基线）

**Decision**: 测试全部基于既有夹具面（fixtures mbti 核证）：
`ScriptedServer::mount/mount_sequence`（任意 status+headers → 决策表
逐行与多跳链）、`conn_request_counts`/`accepted_total`（US-6 连接
计数）、`ResponseScript.body` 各 Plan（1KB 中间体排干）、
`ScriptedPeer` `Capture`/`SlowReceive` 等（剥头字节级断言、取消
竞争）；跨 host 场景用两个 server 实例（不同 port 即异 Address，
语义等价——tests 用 127.0.0.1 两端口）。

**Rationale**: FR/US 所需原语全部在场；夹具零扩展使 spec「外部网络
依赖 0」与包边界（宪法 VI 最小改动）同时成立。21 跳链 =
`mount_sequence` 21 个重定向 + 终态 mount，或对同一路径
`Sequence` 首响应含相对 Location 指向序列路径——implement 期按
夹具语义择一，不影响判据。

**Alternatives considered**: 为「Location 网络路径 `//host:x/x`」
扩展夹具——不需要：Location 值是自由字符串（headers 数组元素），
现有 mount 即可注入任意形态。

**订正（2026-10-28 review 修复批）**：R7「零扩展基线」自落笔后已被
两次登记性例外打破——①T019（converge F1，owner 裁决①）
`captured_request_heads()` 请求头观测面（scripted_server.mbt +31 行）；
②review 修复批 `mount_truncated` 增 `derive_close~` 参数（FR-002 排干
失败毒化判别需剥离 close-token 混淆）。两次均按 tasks Path Conventions
「先红后绿最小扩展并逐处归因」落点并登记于 contracts §3；plan.md
Scale/Scope 与宪法核查表 VI、baseline.md implement 期登记第 8 条以本
订正为准。

## R8 js 形态（非验证面）

**Decision**: 零 `#cfg(js)` 分支、零 js 专属文件。js 上
`@http.Client` 走 fetch 适配层（`redirect:"follow"` 默认）——浏览器
已自动跟随 ⇒ execute 首响应即终态，循环首轮判定不跟随退出，
`prior` 天然 None（spec FR-011「不实现循环、priorResponse 不可用」
的实现形态 = 同一代码被浏览器行为短路，非代码分叉）。js 门禁仅
`moon check --target js`。

**Rationale**: 02 §5 判定「js 实现自循环需改上游 client.js.mbt
（侵入）」——宪法 I/V 双重排除；src 下核证无 js 后端文件（P05 同
形态）。行为差异（js 无 prior、无自循环跳数上限）已录 spec target
矩阵与欠账（M5 收口）。

**Alternatives considered**: js 上以 `redirect:"manual"` 接管（需
上游改动）——宪法 I 否决。

## R9 错误面：TooManyFollowUps

**Decision**: client 包新增
`pub suberror TooManyFollowUps derive(@debug.Debug)` + `pub extend
TooManyFollowUps with @debug.Debug::{to_repr}`（CallCancelled 先例，
http_client.mbt L11-26 同款两件套）。判别式 `err is TooManyFollowUps`。
仅此一项公开面增量（contracts 对账）。

**Rationale**: P05 已确立「显式变体替代消息判别」先例（CallCancelled
↔ IOException("canceled")），同一差异模式应用于
ProtocolException("Too many follow-up requests")；变体入 `.mbti`
满足 spec DoD-2。

**Alternatives considered**: 复用 `CallStateError` 加载荷变体——
状态错误与资源上限语义不同类，混载伤判别性，否决。

## R10 测试映射（FR/US ↔ 元测试）

**Decision**: 命名 `P06-<域><序>`；映射表：

| spec 条目 | 元测试（形态） | 断言要点 |
| --- | --- | --- |
| US-1-1/2（POST 降级） | P06-US1 黑盒 | follow-up 方法/目标、无体与三头、终态、prior 深度 1 |
| US-1-3（HEAD 保持） | P06-US1 黑盒 | HEAD 保持（303 注入） |
| US-1-4/5（PUT/DELETE 降级） | P06-US1 黑盒（T005 落地） | 302→GET / 300→GET（C2/300 修正固化；round3 D-1 补任务落点） |
| US-2（307/308 重放） | P06-US2 黑盒 | Bytes 两跳字节一致；Stream 原样 307；308 同 |
| US-3（Location 三形态/缺失/非法） | P06-US3 黑盒 | resolve 正确跟随；缺失/非法终态 |
| US-4（剥头/保留） | P06-US4 黑盒（Capture） | 跨 host 字节不含两头；同 host 保留 |
| US-5（上限/不跟随集） | P06-US5 黑盒 | 21 跳 raise `err is TooManyFollowUps`；A→B→A 同；304/305/306 透传；300 无 Location 透传 |
| US-6（排干/租约） | P06-US6 黑盒 | 3 跳同 host 连接数=1、第 4 请求干净流；跨 host 新连接+1 |
| FR-001（轮间取消） | P06-WB 白盒 | 桩接缝轮间 cancel → 裸 CallCancelled |
| FR-003（决策表真值） | P06-WB 白盒 | follow_up_request 纯函数逐行真值（含方法×状态码矩阵） |
| FR-005（计数语义） | P06-WB 白盒 | 计数位置（响应后/发送前）；20 次成功 + 第 21 抛出 |
| FR-010（代次折叠） | P06-WB 白盒 | fold_count = 1+跳数；folded_gen 键化复用断言 |
| FR-009（中间 close） | P06-US6 黑盒（T013） | 中间 Connection: close → 后续新连接且旧连接不入池 |
| FR-002（排干+毒化） | P06-US6 黑盒（T012 补②） | 排干失败（夹具 `mount_truncated`）→ 毒化 → 连接不回池（后续同址租借新建 +1）→ 错误透传；成功排干半边由 US-6① 干净流断言承载（round3 补行） |
| SC-008（冻结面） | quickstart 六门 | `.mbti` diff 对账 contracts |

**Rationale**: 决策表纯函数化（follow_up_request 无 IO）使真值矩阵
可白盒穷举；场景类走黑盒保公开面契约。全部基于 R7 夹具，无 sleep。

**Alternatives considered**: 全黑盒——决策表组合爆炸（6 码 × 9 法 ×
3 Location 形态）不宜全走网络夹具，白盒收敛。

## 附加核实记录（implement 首片复核项）

- `Method` 九变体枚举名（Get/Head/Post/…）与
  `to_request_method` 封闭映射——P01 已交付，implement 时以
  `moon ide` peek 定名。
- P05 白盒直调 `exchange_once` 的测试文件与调用点清单（参数化适配
  面）——implement T 首片 `moon test` 全量跑定位。
- `HeadersVBuilder::remove` 大小写不敏感行为与 `get` 一致性——
  P02 契约推定一致，implement 以单测钉住（Authorization 大小写
  变体注入一例）。
