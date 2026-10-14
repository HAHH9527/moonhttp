# 遗留与回补清单（总入口）

> 用途：汇总各里程碑 roadmap 拆分中**显式降级或裁剪、需后续回补**的差异条目。
> 本文件只引用**未完成**的条目；已完成回补的条目保留在对应里程碑子文档中作为
> 历史（状态改为「已回补」并附 spec/commit 引用后，从本文件移除）。
> 后续里程碑（M2–M5）拆分 roadmap 时必读本文件与相关子文档。

## 接入约定

- 里程碑拆分产生欠账时：新建 `deferred-items/deferred-items-mN.md` 明细文件，
  并在本文件「子文档索引」与「未完成条目」表登记。
- 条目回补完成时：子文档改状态附引用 → 本文件移除该行。
- 上游侵入点编号（I1–I12）沿用原报告（`proj-init-docs/okhttp-on-async-http/README.md`
  §3 侵入点总表）；凡涉及上游仓库改动，**必须事先人工批准**（宪法原则 I）。

## 子文档索引

| 里程碑 | 明细文件 | 条目数（未完成/总数） |
| --- | --- | --- |
| M1 性能核心 | [`deferred-items/deferred-items-m1.md`](deferred-items/deferred-items-m1.md) | 13 / 13 |
| M2 完整门面 | （待 M2 拆分时创建） | — |
| M3–M5 | （待对应里程碑拆分时创建） | — |

## 未完成条目（跨里程碑汇总）

| # | 条目 | 回补位置 | 状态 | 明细 |
| --- | --- | --- | --- | --- |
| F1 | 拦截器链（M1 内部管线 → 公开双层拦截器 API） | M2 / 04 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F2 | 代理支持（ProxyConfig/代理池/absolute-form·I5） | M2 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F3 | DNS 缓存（L1 自组版 + 上游 PR·I2） | M2 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F4 | RequestBody::File 形态（fs stat 验证前置） | M2 / 09 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F5 | ResponseBody `json()`/`char_stream()` | M2 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F6 | 401/407 认证 follow-up（Authenticator·I4 可选） | M2 / 08 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F7 | 304 缓存语义（M1 终态透传 → 缓存合并，用户可见行为变化） | M4 / 05 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F8 | 408 可选重试（opt-in，需求驱动） | 未排期 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F9 | wasm-gc stub 与 js 适配层收口 | M5 / 16 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F10 | @http 内部逐段 blit（基准驱动·I8） | 未排期（M3 评估） | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F11 | 响应头顺序不可保真（基准驱动·I6/I8） | 未排期 | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F12 | 敏感信息掩码的运行期开关（P01 交付 derive(Debug) 默认明文输出，经宪法 v1.2.0 展示例外程序人工确认） | M3（Logger/EventListener） | 待回补 | [M1](deferred-items/deferred-items-m1.md) |
| F13 | 敏感信息脱敏专版（默认脱敏 + 按需展示形态，覆盖 HeadersV/调试输出及后续值类型） | M3（随 Logger/EventListener 与 F12 一并设计） | 待回补 | [M1](deferred-items/deferred-items-m1.md) |

## 按里程碑速查（仅未完成）

- **M2 拆分须核对**：F1–F6（6 条）。
- **M3 拆分须核对**：F10 评估决策、F12（可配置掩码开关 + 补宪法「不安全配置
  opt-in」条款）、F13（脱敏专版，与 F12 一批设计）；另注意 F2 随带的 Address
  `trust` 字段生效。
- **M4 拆分须核对**：F7（行为变化需 changelog）。
- **M5 拆分须核对**：F9 + 汇总 M1–M4 全部 js 降级清单。
- **未排期**：F8（需求驱动）、F10、F11（基准驱动）。
