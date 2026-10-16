# M1 遗留与回补清单

> 用途：M1 工作包拆分（`docs/roadmap/M1/`）中**显式降级或裁剪、需后续里程碑回补**
> 的条目明细。总入口与跨里程碑汇总见 [`../deferred-items.md`](../deferred-items.md)；
> 差异源头与理由详表见 `docs/roadmap/M1/README.md` 第 3 节（D1–D9）。
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

## 与里程碑的对应速查

- **M2**：F1（拦截器链）、F2（代理）、F3（DNS 缓存）、F4（File 体）、F5（便捷方法）、
  F6（认证）——共 6 条，M2 拆分时逐条核对。
- **M3**：F4 之外另注意 D3 的 `trust` 指纹字段（07-tls-security 的自定义信任/证书固定
  需要它进 Address 池键；该字段本身随 F2 的 Address 扩展一并考虑，07 落地时生效）；
  **F12** 可配置掩码开关与 **F13** 脱敏专版随 Logger/EventListener 一批设计，
  并同批补宪法「不安全配置 opt-in」条款。
- **M4**：F7（304 语义变化）。
- **M5**：F9（target 收口），并汇总核对 M1–M4 全部 js 降级清单。
- **未排期（基准驱动/需求驱动）**：F8、F10、F11、F14、F15。
