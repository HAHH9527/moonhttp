# M1 遗留与回补清单

> 用途：M1 工作包拆分（`docs/roadmap/M1/`）中**显式降级或裁剪、需后续里程碑回补**
> 的条目明细。总入口与跨里程碑汇总见 [`../deferred-items.md`](../deferred-items.md)；
> 差异源头与理由详表见 `docs/roadmap/M1/README.md` 第 3 节（D1–D17）。
> 后续里程碑（M2–M5）做 roadmap 拆分时必读：逐条核对，将到期条目纳入对应工作包。

## 使用约定

- **状态**：`待回补` / `已回补（附 spec/commit 引用）` / `裁定不做（附理由）`。
  条目回补完成后：本文件改状态并附引用，同时从总入口的「未完成条目」表移除。
- 上游侵入点编号（I1–I12）沿用原报告 §3 侵入点总表；凡涉及上游仓库改动，
  **必须事先人工批准**（宪法原则 I）。
- M1 内部消化、无欠账的差异（D2 enqueue 归属、D8 夹具自建）不收录本文件。

## 回补清单

| # | 条目 | M1 现状（降级口径） | 回补位置 | 回补要点 | 状态 |
| --- | --- | --- | --- | --- | --- |
| F1 | 拦截器链（D1） | P05 交付内部执行管线，预留 exchange 接缝；无公开拦截器 API | **M2 / 04-interceptors** | 双层拦截器链（[应用]→RetryAndFollowUp→Bridge→Cache→Connect→[网络]→CallServer）插进 P05 接缝；M1 的重试/重定向循环（P06/P07）与自动头逻辑迁入对应拦截器时**必须保持行为等价**（M1 全部测试作为回归基线） | 待回补 |
| F2 | 代理支持（D3） | Address 仅直连三元组；无 ProxyConfig/代理连接池 | **M2**（03 §3.6） | Address 增加 `proxy` 字段进池键；代理 Client 自身池化；http-over-proxy absolute-form 依赖上游 Host 覆盖 PR（**I5，~5 行，须人工批准**），PR 前维持 CONNECT-only 或记录降级 | 待回补 |
| F3 | DNS 缓存（D3） | 每次新建连接全量 getaddrinfo，无缓存 | **M2**（L4 / I2，03 §3.5） | 先交付 L1 自组非侵入版（`Map[host,(Addr 列表, expiry)]` + 自组竞速）；上游 PR（**I2，~30 行，须人工批准**）合并后切换共享版 | 待回补 |
| F4 | RequestBody::File 形态（D5） | 仅 Bytes/Stream 两形态 | **M2 / 09-request-bodies** | File(path, len) 重放 = 重开文件；fs stat 对应长度验证是前置（特性目录 09 行标注的待验证项） | 待回补 |
| F5 | ResponseBody 便捷方法（D6） | 仅 `bytes()`/`text()` | **M2** | `json()`（引 @json 依赖）与 `char_stream()`（原文已标 M2） | 待回补 |
| F6 | 401/407 认证 follow-up（D7） | 一律终态返回，无 Authenticator | **M2 / 08-auth** | 决策表回补 401/407 行；407 优雅化可选（**I4，~15 行**，现有绕行可用则不侵入）；认证路径的 HeadersV 需绕过 Map 折叠（quoted-string 逗号，P01 已留例外条款） | 待回补 |
| F7 | 304 缓存语义（D7） | 304 终态透传给调用方 | **M4 / 05-cache** | 缓存层存在后 304 与缓存合并、自动转条件 GET——这是 M1 → M4 的**用户可见行为变化**，须在 M4 spec 与 changelog 显式记录 | 待回补 |
| F8 | 408 可选重试（D7） | 不跟随不重试 | 未排期（原文即标可选） | OkHttp 无此默认；仅当用户提出需求时作为 opt-in 纳入 | 待回补 |
| F9 | wasm-gc stub 与 js 适配层（D9） | wasm-gc/js 依宪法 v1.2.0 原则 V（:67-77）「暂不验证」（2026-10-14 起），非 M1 例外；各包 target 矩阵显式标注并挂欠账 | **M5 / 16-target-support** | wasm-gc 跟踪上游 runtime、M5 前不建 stub（宪法 :75-76）；js fetch 适配层与能力清单收口（M5 起 js 恢复 check 门禁，:130-133；M1–M4 各包「未验证」项届时汇总核对） | 待回补 |
| F10 | @http 内部逐段 blit（D4 尾巴） | L3 只做到缓存折叠 Map；发送路径 Map 迭代+逐段 blit 仍在 @http 内部 | 未排期（**I8**，基准驱动，M3 评估） | 仅当 P10 基准证明请求头序列化是热点才推进；属上游深水区，须人工批准 | 待回补 |
| F11 | 响应头顺序不可保真 | @http 响应侧无序 Map + 逗号合并，重建 HeadersV 为遍历序；各包验收禁止断言线上顺序 | 未排期（**I6/I8**，基准驱动） | 保真需改 `read_headers` 字节域扫描（I6）；若推进，同步解除 P02 及下游「不得断言顺序」的验收限制 | 待回补 |
| F12 | 敏感信息掩码的运行期开关（P01 决策 N4-A → R3-H1-A 修订） | P01 交付 derive(Debug) **默认明文**输出（无逃生口、无包级开关；宪法 v1.2.0 :112-117 展示例外程序，人工确认留痕＝分析报告 R3-M1），测试与 `.snap` 样例值须为合成占位串 | **M3**（可观测与安全：Logger/EventListener 落地时） | 随 Logger/EventListener 一并设计可配置掩码（全局或作用域级、跨 native/wasm/wasm-gc/js 语义一致），与 F13 脱敏专版同批；同批补宪法「技术约束与合规」中留待后期条目的「不安全配置 opt-in」 | 待回补 |
| F13 | 敏感信息脱敏专版（P01 决策 R3-H1-A/R3-M3-A） | P01 不承诺脱敏：全部公开类型 derive(Debug) 默认明文，无手写 impl、无逃生口（`specs/001-m1-p01-core-value-types/spec.md` FR-013/A8、plan「例外跟踪」节） | **M3**（可观测与安全） | 「默认脱敏 + 按需展示」完整形态随 Logger/EventListener 管线统一设计（与 F12 一批），覆盖 HeadersV/HeadersVBuilder 及后续 Request/Response 等值类型；错误消息只携带定位片段与 `to_string` 不含 userinfo 两条不因专版撤销 | 待回补 |
| F14 | `text()` 受支持 charset 集扩展（P02 裁决 C4，2026-10-15；2026-10-16 owner 裁决 B 覆写集外语义） | M1 解码集仅 {UTF-8}：缺省/声明 UTF-8（任意大小写、带引号）按 UTF-8 解码；**集外 charset（latin1/gbk 等）按 UTF-8 降级解码（`decode_lossy`、畸形序列 U+FFFD）并输出一条 stderr 告警（唯一出口包内私有 `warn_charset_fallback`），不 raise、不并入 P02 FR-012 错误类型**（`specs/002-m1-p02-request-response/spec.md` FR-007/A4） | 未排期（需求驱动） | 引入对应解码依赖（latin1 零码表成本低、gbk 需码表/第三方解码），扩展 FR-007 受支持集与验收场景；扩展后按声明集解码、未知集仍降级 UTF-8；保持 OkHttp `string()` 语义（charset 解码、缺省 UTF-8） | 待回补 |
| F15 | `tag` 占位升级评估（P02 裁决 C2，2026-10-15） | M1 tag 保持占位 `Unit?`：字段就位、语义零承诺、无按 tag 定位/批量取消（`specs/002-m1-p02-request-response/spec.md` FR-002/A2） | 未排期（需求驱动，随 P05 Call.cancel / P09 Dispatcher 出现按 tag 批量定位需求时评估） | 评估泛型/任意值 tag 升级；破坏性变更走 spec 变更流程（0.x 实验期允许），`.mbti` 冻结面逐项审视 | 待回补 |
| F16 | abortive close（RST）/半关闭（shutdown）注入能力缺口（2026-10-18，specs/003 澄清 D2） | 上游 moonbitlang/async 的 src/socket 全目录无 shutdown、socket.c 的 setsockopt 无 SO_LINGER，Tcp 公开面只有幂等全双工 close（无方向参数）——只经公开 API 无法确定性构造 RST/半关；P03 夹具交付为 close 注入 + 依实测钉死的 FIN/RST 观测清单（`specs/003-m1-p03-test-fixtures/spec.md` 澄清 D2/证据 E3/E5；P03 plan 已显式否决「本项目自写 extern "C" 绑定补上游缺口」） | 未排期（**需人工批准的上游 PR 候选**：为 @socket 增补 shutdown 方向参数或 SO_LINGER 选项，属宪法 I 上游改动，须事先人工批准；侵入点编号＝新增候选·待分配） | 上游能力落地后，P03 夹具（B-10）与 P07 故障注入把 RST 从「观测清单」升级为「可确定性注入」；观测清单口径保留为跨平台事实记录。**P03 已交付部分（2026-10-18）**：close 注入 + 双 target 实测观测清单已归档（specs/003-m1-p03-test-fixtures/fr015-observations.md，native/wasm 各三行；双方向 pending_unread 形态——客户端请求未读 → OSError、夹具写入未读 → ReaderClosed），确定性 RST 仍待上游，状态不变 | 待回补 |
| F17 | @http 客户端错误面无法区分响应截断点（2026-10-18，specs/003 澄清 D3） | `src/io/reader.mbt:217-224` 使 read_until 在 EOF 且缓冲非空时返回 Some(残余串)，`src/http/parser.mbt:401-403` 因此对半截状态行也拿到 Some，错误下移为 BadRequest 或在 :146/:167/:259 抛 ReaderClosed；@http 不暴露部分解析信号（`specs/003-m1-p03-test-fixtures/spec.md` 澄清 D3/证据 E4） | 未排期（需求驱动；若要真区分需上游暴露解析进度信号——**需人工批准候选**，侵入点编号＝新增候选·待分配） | 影响：P07 判据按**错误类型分流**——`ReaderClosed`（EOF 路径，parser.mbt:401-403）可重试、`BadRequest`（协议错误族，parser.mbt:404/:410-413）不可重试但毒化；钉死集合 {BadRequest, ReaderClosed} 仅是**可观测集合、不等同可重试集合**，不得以「客户端能观测到状态行已解析」为判据（P07 种子已按此改写，对齐 OkHttp RetryAndFollowUpInterceptor.kt:171-173/:197）；上游暴露解析进度信号后再评估精细判定。**P03 已交付部分（2026-10-18）**：E4/D3 推演的残余串下移路径获首次实测实证——drain 后 MidHeaderLine(8) 截断点客户端错误实测落 BadRequest（parser.mbt:404），Nothing/MidStatusLine(15)/AfterStatusLine 落 ReaderClosed（B-11 竞态自证 10/10 零翻转，t004-record.md 账目），钉死集合口径未动 | 待回补 |
| F18 | `TcpServer::accept` 并发调用不安全（2026-10-18，specs/003 T008 实测） | 同一监听句柄并发挂 2 个 accept：**native 直接 PanicError 崩溃（exit 0xc0000409）、wasm/moonrun 悬挂不醒（>120s 无结局）**——双 target 探针实测（裸 `TcpServer::accept` ×2 + 2 客户端 connect，零夹具代码复现）；机制锚点 `network_windows.mbt:194-213` accept_windows 经 `handle.wait_read_result` 在同一句柄挂等待；上游唯一自证可行形态即 `run_forever`（tcp.mbt:141-172）循环内串行 accept（三分支 tcp.mbt:223/:231/:239）+ 连接经任务组 spawn_bg 并发处理。P03 夹具已按 owner 裁决 A 以 `serve_n` 收口 accept 循环（`specs/003-m1-p03-test-fixtures/data-model.md` 实体 2 注记：原「不设 serve_n」前提被 T008 实测推翻），测试代码保持零 accept 循环（FR-012）；B-04 行为判据不弱化（客户端侧真实并发 N=8 + 交错自证断言） | 未排期（**需人工批准候选**：向 moonbitlang/async 提 issue 确认并发 accept 语义/修复或文档显式声明串行约束，属宪法 I 上游改动，须事先人工批准；侵入点编号＝新增候选·待分配） | 上游若支持/修复并发 accept，再评估放开 P03 `serve_n` 的串行 accept；此前 P07+ 多连接并发场景的服务端形态一律走 `serve_n`（或逐条 serve_once） | 待回补 |
| F19 | IPv6 字面量建连 URI 缺方括号（Host 头非 RFC 3986/7230 权威形态；2026-10-21 code-review 430423f6..HEAD 发现·MEDIUM，agent 独立核实锚点） | `acquire` 组装 `\{scheme}://\{host}:\{port}`（`src/client/client.mbt:241`；specs/004 contracts/pool-api.md §2 步骤 3 同款登记）；`Address::new` 按 FR-014 剥括号存储（client.mbt:33）⇒ IPv6 字面量拼出 `http://::1:8080`——上游 `resolve_host` 贪婪正则碰巧切对（request.mbt:55-72：`.*` 贪婪回溯后 host=`::1`、port=8080，TCP 可达），但 Host 头构造期固化为无括号形态（上游 client.mbt:58，R1 C-10），严格源站可拒；P04 无 IPv6 端到端用例（E④ 仅键语义）。属契约级潜在缺陷（代码与契约一致，非实现走样），故按 roadmap 纪律登记而非在已收敛的 P04 内热修 | **M1 / P05**（执行管线接线——acquire 建连路径的首个真实消费方） | 组装时对含 `:` 的 host 重新包裹 `[]`（与 P01 `HttpUrl::to_string` 行为对齐）；同步修订 contracts/pool-api.md §2 的 uri 形态登记（走 spec 变更流程回改 FR-008/D13 口径）；补 IPv6 loopback 端到端回归用例（夹具 listen 形态若仅 IPv4 需先扩，随 P05 评估） | 待回补 |
| F20 | P06 follow-up/重定向性能量化场景缺失（2026-10-28，specs/006-m1-p06-redirects converge F2 → T020；M1 README D17） | P06 交付的 follow-up 循环路径（中间体排干 O(body)、同 host 租约保持消除归还-重取、代次重折叠每代次恰一次、prior 链每请求一次装配重建）无基准场景承载：P10 种子场景矩阵（14 §5）仅「连接形态×请求形态×gzip」，全文无重定向/follow-up；宪法 II「性能相关改动必须附带基准数据」的量化义务悬空（行为正确性已由 specs/006 SC-003/SC-006 断言，性能数据未量化） | **M1 / P10**（基准套件与性能门禁；P10 种子场景矩阵已按 D17 补 follow-up 场景行） | P10 specify 时将 follow-up 场景纳入基准实现与报告：单跳降级、多跳同 host（租约保持）vs 逐跳重建连接对照、跨 host 换租；含 prior 链每请求一次装配重建的开销观测（specs/006 converge 非任务观察：attach_prior 对每次 execute 重建终态 Response，量化落地 P10 后即暴露）；量化结果入 P10 基线归档（docs/benchmarks/），与 round1–3 口径对照 | 待回补 |
| F21 | followRedirects/followSslRedirects 关闭跟随开关缺失（2026-10-28，specs/006-m1-p06-redirects review 修复批登记；P08 范围补登） | P06 spec 非目标（spec.md:214-216）与 OkHttp 映射表（:371）把 followRedirects/followSslRedirects 关闭跟随开关钦定归 P08 builder 配置位，但 P08 工作包全文零提及、deferred-items 零登记——里程碑拆分时静默丢失。M1 行为面＝恒跟随、恒允许 scheme 变更（＝OkHttp 两开关默认 true）；开关关闭后 3xx 一律终态透传 | **M1 / P08**（四类超时与 per-call 配置；builder 配置位随 new_builder 派生面一并交付） | P08 specify 时把两开关纳入 builder 配置面与验收场景（关闭 followRedirects ⇒ 3xx 终态透传、prior 链不累积；followSslRedirects 关闭 ⇒ 跨 scheme 降级跳终态），行为对齐 OkHttp followRedirects(action) 语义；P06 交付状态不回改 | 待回补 |

## 与里程碑的对应速查

- **M1 内 P05**：F19（IPv6 URI 方括号修正 + 契约 §2 回改 + IPv6 回归用例，
  随执行管线接线一并落地）。
- **M1 内 P10**：F20（follow-up/重定向场景入基准矩阵 + 量化归档，
  M1 README D17）。
- **M1 内 P08**：F21（followRedirects/followSslRedirects 开关）。
- **M2**：F1（拦截器链）、F2（代理）、F3（DNS 缓存）、F4（File 体）、F5（便捷方法）、
  F6（认证）——共 6 条，M2 拆分时逐条核对。
- **M3**：F4 之外另注意 D3 的 `trust` 指纹字段（07-tls-security 的自定义信任/证书固定
  需要它进 Address 池键；该字段本身随 F2 的 Address 扩展一并考虑，07 落地时生效）；
  **F12** 可配置掩码开关与 **F13** 脱敏专版随 Logger/EventListener 一批设计，
  并同批补宪法「不安全配置 opt-in」条款。
- **M4**：F7（304 语义变化）。
- **M5**：F9（target 收口），并汇总核对 M1–M4 全部 js 降级清单。
- **未排期（基准驱动/需求驱动/需人工批准候选）**：F8、F10、F11、F14、F15；
  F16（上游 PR 候选：shutdown/SO_LINGER，**须事先人工批准**，宪法 I）、
  F17（上游解析进度信号候选，**须人工批准**）、
  F18（上游并发 accept 语义确认/修复候选，**须人工批准**）。
