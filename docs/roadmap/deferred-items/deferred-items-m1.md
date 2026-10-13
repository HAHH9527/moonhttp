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
| F9 | wasm-gc stub 与 js 适配层（D9） | wasm-gc 无 stub、js 仅 `moon check` + 降级清单 | **M5 / 16-target-support** | wasm-gc 明确报错 stub（跟踪上游 runtime）；js fetch 适配层与能力降级清单收口（M1–M4 各包 js 降级项届时汇总核对） | 待回补 |
| F10 | @http 内部逐段 blit（D4 尾巴） | L3 只做到缓存折叠 Map；发送路径 Map 迭代+逐段 blit 仍在 @http 内部 | 未排期（**I8**，基准驱动，M3 评估） | 仅当 P10 基准证明请求头序列化是热点才推进；属上游深水区，须人工批准 | 待回补 |
| F11 | 响应头顺序不可保真 | @http 响应侧无序 Map + 逗号合并，重建 HeadersV 为遍历序；各包验收禁止断言线上顺序 | 未排期（**I6/I8**，基准驱动） | 保真需改 `read_headers` 字节域扫描（I6）；若推进，同步解除 P02 及下游「不得断言顺序」的验收限制 | 待回补 |

## 与里程碑的对应速查

- **M2**：F1（拦截器链）、F2（代理）、F3（DNS 缓存）、F4（File 体）、F5（便捷方法）、
  F6（认证）——共 6 条，M2 拆分时逐条核对。
- **M3**：F4 之外另注意 D3 的 `trust` 指纹字段（07-tls-security 的自定义信任/证书固定
  需要它进 Address 池键；该字段本身随 F2 的 Address 扩展一并考虑，07 落地时生效）。
- **M4**：F7（304 语义变化）。
- **M5**：F9（target 收口），并汇总核对 M1–M4 全部 js 降级清单。
- **未排期（基准驱动/需求驱动）**：F8、F10、F11。
