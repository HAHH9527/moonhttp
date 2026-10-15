# Quickstart：验证请求/响应/体值模型与定长帧可用（M1-P02）

**目的**：证明 P02 端到端可用——值模型、转换层、生命周期契约全部经
`moon test` / `moon check` 验收；线上字节断言（US-2 场景 1/2）依赖 P03
裸 TCP 对端夹具（见前置条件 3）。

## 前置条件

1. 工具链：`moon version` ≥ 0.1.20260920（本仓库实测 0.1.20261012，P01
   `error.mbt` 留痕）；`moon.mod` 已钉
   `moonbitlang/async@0.22.4`（既有）。
2. `src/core/moon.pkg` 已含两条新增 import（research R8）：
   `moonbitlang/async/io`、`moonbitlang/core/encoding/utf8`。
3. **P03 裸 TCP 对端夹具**（spec 前置依赖）：US-2 场景 1/2 的线上字节
   断言由其承载；当前仓库尚无 P03 产物——夹具未落地前，步骤 2 的线上
   断言组以 P03 交付为排期前置（tasks 阶段处理依赖顺序），其余步骤
   不受阻。

## 验证步骤

### 1. 双 target 测试（核心验收，SC-001）

```text
moon test --target native   # 期望：全绿
moon test --target wasm     # 期望：全绿
```

**看什么**：US-1–US-5 验收场景与 spec 边界用例全部有对应断言，锚点逐条
通过（[contracts/request.md](contracts/request.md)、
[contracts/response.md](contracts/response.md)、
[contracts/conversion-errors.md](contracts/conversion-errors.md) 的锚点表）：
方法/体矩阵双向校验、Bytes 构造期长度校验、重放逐字节一致、转换层纯函数
属性（N 次转换逐字节相同 + Content-Length/Content-Type 注入 + fragment
剥除）、with_progress 累计单调且终值 = content_length、text() charset
三态（utf-8 任意写法/集外报错/缺省）、0 字节响应、流式三类生命周期事件
（Consumed/Dropped/Abandoned 互斥时序，桩 = `@io.MemoryReader`/`pipe`）、
Response.headers 重建与 P01 折叠互逆。

### 2. 线上字节断言（US-2 场景 1/2，SC-002；前置 P03 夹具）

```text
# 经转换层输出直接驱动 @http.Client（不经 P05），P03 对端捕获原始字节
# Bytes 体（content_length=Some(n)）：含 `Content-Length: n`，无 `Transfer-Encoding`
# Stream 体（None）：含 `Transfer-Encoding: chunked` 与块编码
```

**看什么**：定长帧真正触发 `SendingFixed`（research R3 send.mbt:343-345
机制）、chunked 形态含块编码；**Bytes + with_progress 组合**线上仍
`Content-Length: n`、无 `Transfer-Encoding`——进度分块不得降级 chunked
（锚点见 [contracts/conversion-errors.md](contracts/conversion-errors.md)
条款 7 与锚点表末行）。js 不适用（fetch 语义由浏览器管理，仅 API
层验收，spec A8）；wasm 侧以转换层输出断言为准（线上捕获仅 native）。

### 3. 零警告门禁与接口冻结（宪法 VI；对齐 P01 SC-004 口径）

```text
moon check                  # 期望：零错误零警告（含 [0079]/[0027]）
moon check --target wasm    # 期望：零错误零警告
moon info && moon fmt       # 期望：干净无 diff 残留
```

**看什么**：`src/core/pkg.generated.mbti` 增量 = Request/RequestBuilder/
RequestBody/BodySource/Response/ResponseBody/HttpMessageError/
ResponseBodyEvent + `to_http_request`/`from_http`/`with_progress` +
生命周期查询（`consumed`/`dropped`/`drop`）+ 各 `derive(Debug)` 类型配套
的 `to_repr`（含 HttpMessageError/ResponseBodyEvent——N1-A 消 [0079]
口径，research R1）——**不得**出现自立 Writer
trait（C1）、泛型/任意值 tag（C2）、日志/序列化输出类签名、按 tag 定位
API 或其他意外泄漏。手写 Debug 的三个类型（BodySource/RequestBody/
ResponseBody）计入冻结清单逐条审视（research R10）。验证面为 native/wasm；
js 与 wasm-gc「暂不验证」（宪法 V；欠账 F9）。

### 4. 输出面与测试纪律抽查（宪法敏感信息条款；沿 P01 A9）

**看什么**：① 错误消息只带定位片段（方法名/长度对/charset 名），不回显
头值、体字节、URL 全文；② RequestBody/ResponseBody 的 Debug 不印体内容；
③ 测试与 `.snap` 中敏感头样例值为合成占位串（如 `Bearer test-token-123`），
`git grep` 无真实形态凭证串。

### 5. OkHttp 移植对拍清单（宪法 III/IV）

**看什么**：测试文档列明移植组（Request.Builder 方法/体矩阵、
MediaType charset 参数解析、string() 替换式解码语义）与显式差异组
（BOM 不嗅探、响应头序不保真、File/json 裁剪、cookies 不建 Jar），
来源注明 `OkHttp 5.5.0 (Apache-2.0)`；C5 矩阵附 research R2 佐证链，
5.5.0 tag 行号复核项在 tasks 中闭环。

## 通过判据

步骤 1/3/4/5 全部符合 + 步骤 2（P03 就位后）稳定通过 → P02 包级 DoD
达成（spec SC-001–SC-006；SC-006 的量化归 P10 基准），可进入 P04/P05。

## 已知不验证项（显式排除）

- 性能基准量化：P10「POST 定长 vs chunked」场景汇总（宪法 II；本包以
  SC-002 线上形态断言守住机制不回归）。
- js 线上断言与 wasm-gc：暂不验证（宪法 V；spec A8，欠账 F9）。
- 发送期 catch/映射执行、归池/毒化真实行为：归 P05/P04（FR-010/FR-006；
  本包只验收契约与默认行为）。
