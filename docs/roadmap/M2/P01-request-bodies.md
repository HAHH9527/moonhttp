# P01 请求体构造器与响应便捷解析（FormBody/Multipart/File/进度/json）

> 里程碑：M2 完整门面 ｜ 前置依赖：M1-P02（RequestBody/BodySource）、M1-P03（夹具）｜ 人力估计：~4.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/09-request-bodies/README.md` §1–§8；
> 回补 M1 欠账 **F4**（RequestBody::File 形态）与 **F5**（ResponseBody `json()`/`char_stream()`）
> 侵入性：非侵入（fs stat 待验证项见澄清 C1）｜ 建议特性 slug：`m2-p01-request-bodies`

## 功能描述（speckit 输入种子）

为 moonhttp 交付 OkHttp recipes 面的**请求体构造器全家桶与响应便捷解析**：
`FormBody`（`application/x-www-form-urlencoded`，构造期一次 percent-encode、
Content-Length 已知走定长帧）、`MultipartBody`（boundary 自动生成、总长预计算、
大文件流式拼装不进内存）、`RequestBody::file(path)`（重开文件重放，长度来自
fs 元数据或显式传入）、`RequestBody::writer`（一次性回调式流）、上传/下载
`with_progress` 进度包装；响应侧补齐 `ResponseBody::json[T]()`（泛型反序列化）
与 `char_stream()`（按 Content-Type charset 选解码，默认 UTF-8）。
全部构造器保证「总是给出 Content-Length」以触发底座定长帧（SendingFixed）。

## 范围

包含：

- `FormBody::Builder`：`add`/`add_encoded`/`build`；percent-encode 规则对齐
  okhttp FormBody（保留 `*` `-` `.` `_`，空格→`+`，其余非 [A-Za-z0-9] 编码为
  `%XX`；复用 M1-P01 core 包既有 percent 基础）。
- `MultipartBody::Builder`：`setType`（mixed/form-data/related/alternative）、
  `addFormDataPart`/`addPart`；boundary 生成（32 位随机 hex + `moonbit-multipart-`
  前缀）；惰性流式拼装 + 总 Content-Length 预计算（各段头与文本段全已知，
  文件段取 fs 大小/显式长度）。
- `RequestBody::file(path, length?)`：`@async/fs` 打开、重放 = 重开文件
  （F4 回补）；`RequestBody::writer(content_length?, f)` 一次性流（不可重放）。
- `with_progress`（上传/下载对称）：Bytes 分 32KB 块回调；Stream/文件用计数
  Writer 包装透传（对齐 okhttp ForwardingSink recipe）。
- `ResponseBody::json[T : FromJson]()`（引 `@json` 依赖；错误包装
  `JsonDecodeError`）、`ResponseBody::char_stream()`（charset 表至少
  utf-8/latin-1）（F5 回补）。

非目标（显式排除）：

- 请求体 gzip 压缩拦截器（recipes 示例在 M2-P06，实现属 04/L9 范畴，P03/P06 承接）；
- br/zstd 透明解压加宽（L9，M3）；
- Moshi 式适配器体系（`json[T]` 即等价落点，不再建适配器层）；
- 文件 body 的 fs stat 上游扩展（若 C1 验证不可得，走显式长度兜底，不侵入）。

## 用户故事种子

### US-1 FormBody 定长帧（P1）

作为使用者，我用 `FormBody::Builder` 构造表单体发 POST；线上形态是定长帧且
编码正确。

**独立测试**：P03 捕获对端 + echo 服务端；不依赖本里程碑其他包。

**验收场景**：

1. Given `add("a", "hello world")`，When build 后经捕获对端发送，Then 线上字节
   含 `Content-Length` 且不含 `Transfer-Encoding`，body 为 `a=hello+world`。
2. Given 编码矩阵（空格/中文/`*` `-` `.` `_` 保留/预编码 `add_encoded`），
   When 逐一发送，Then 服务端回显解码值逐项正确。
3. Given 空 FormBody（零键值），When 发送，Then `Content-Length: 0` 正常。

### US-2 MultipartBody 流式与逐字节形态（P1）

作为使用者，我用 MultipartBody 混合文本与文件段上传大文件；线上字节符合
`multipart/form-data` 且内存不随文件大小膨胀。

**验收场景**：

1. Given 文本段+二进制段+文件段各一，When 发送至捕获对端，Then 逐字节断言
   boundary 行/CRLF/各段 `Content-Disposition`/终结段 `--boundary--` 全部正确。
2. Given >100MB 文件段，When 上传，Then 进程内存峰值不含文件整体
   （流式泵送断言，native 侧观测 RSS）。
3. Given 同一 MultipartBody 重放（重定向场景），Then 文件段重开文件重发、
   两次线上字节一致。
4. Given 正文中包含 boundary 串的构造攻击用例，Then 生成 boundary 不与正文
   碰撞（前缀+随机重试策略）。

### US-3 文件与一次性流式 body（P1）

作为使用者，我用 `RequestBody::file` 上传文件、用 `RequestBody::writer` 流式
生成 body。

**验收场景**：

1. Given 本地文件，When `RequestBody::file` 上传，Then 服务端收到与文件逐字节
   一致的 body、`Content-Length` 等于文件大小。
2. Given 同一 file body 经 3xx 重定向重放，Then 文件被重新打开重发（句柄不跨
   请求复用）。
3. Given writer body 已写出部分字节后触发重试条件，Then 该 call 以「不可重放」
   错误终止（对齐 M1-P02 流式不可重试语义），不产生半截二次发送。

### US-4 上传/下载进度（P2）

作为使用者，我注册进度回调观察字节增量。

**验收场景**：

1. Given 1MB Bytes 体 + `with_progress`，When 上传，Then 回调增量之和 == 总长、
   回调次数符合分块预期。
2. Given 滴流下载体 + `with_progress`，When 读取，Then 下载增量之和 == 总长。
3. Given 上传中途 cancel，Then 回调停止、不再触发。

### US-5 响应便捷解析（P2）

作为使用者，我对 JSON 响应调 `json[T]()`、对文本响应按 charset 解码。

**验收场景**：

1. Given `Content-Type: application/json` 响应体，When `json[T]()`，Then 反序列化
   成功且 roundtrip 相等。
2. Given 非法 JSON，Then 返回 `JsonDecodeError` 类错误（可判别、不 panic）。
3. Given `Content-Type: text/plain; charset=latin-1`，When `char_stream()`，
   Then 按 latin-1 解码；无 charset 时默认 UTF-8。

## 边界用例

- FormBody 键值含 `%` 与已编码串混用（`add` vs `add_encoded` 语义分界）；
- Multipart 零 part / 仅头无 body 的退化段；
- boundary 随机源不可用时的行为（构造期报错，非静默退化）；
- 文件在重放间隙被删除/截断（重开失败 → 该 call 以 IO 错误终止）；
- json[T] 对超大响应的内存行为（buffered 语义，文档标注不做流式 JSON）；
- latin-1 与 UTF-8 的 charset 名大小写/别名容错。

## 需求种子

- **FR-001** FormBody/MultipartBody/File body MUST 给出已知 Content-Length
  （定长帧）；writer body 允许未知长度（chunked）。
- **FR-002** MultipartBody MUST 惰性流式拼装，总长预计算；文件段经
  `write_reader` 整块泵送，内存上界 = 发送缓冲 + fs 读缓冲。
- **FR-003** File body 重放 MUST 重开文件；writer body MUST 标记不可重放。
- **FR-004** 进度回调 MUST 不引入每字节分配（Int64 计数器透传）。
- **FR-005** `json[T]` 错误 MUST 包装为可判别错误类型；charset 解码失败行为
  在 spec 显式记录。
- **FR-006** boundary MUST 满足唯一性（随机 + 前缀 + 碰撞重试），文档声明
  非密码学随机。

## 关键设计要点

- percent-encode 复用 core 包（M1-P01 `percent.mbt`）既有实现，缺失规则增量补齐。
- 定长帧接线：已知长度经 `extra_headers~{"Content-Length": n}` → 底座
  `SendingFixed`（M1-P02 转换层机制，本包只负责产出已知长度）。
- **fs stat 验证是 F4 回补的前置**（原报告 09 §4 待验证项）：`@async/fs` 若有
  stat/metadata 则取文件长度；不可得则 `file(path, length)` 显式长度兜底
  （非侵入），验证结论写入 spec。若未来决定扩上游 fs，属新侵入点，须人工批准。
- json 依赖引入 `moonbitlang/x` 或 core 的 @json（版本在 plan 定），依赖面变化
  过 `.mbti`/moon.mod diff 审视。
- 进度 Writer 包装实现 `@io.Writer::write_once` 计数后透传，零额外拷贝。

## 侵入性与宪法合规

- 全部构造器/进度/便捷解析**非侵入**（纯上层）。
- 宪法 II：FormBody 构造期一次编码、请求期零额外分配；Multipart 流式定长帧
  直通 `SendingFixed` 泵送——性能口径在 P06 门禁复验。
- 宪法 VI：`json` 依赖引入是最小依赖面决策（替代自写解析器）。
- 宪法 I：fs stat 不可得时**不**启动上游扩展，走显式长度兜底。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 全功能；wasm 的 fs 走宿主注入 |
| js | ⚠️ | FormBody/MultipartBody/进度可用（body 一次性传给 fetch）；writer 流式上传退化为缓冲后发送；文件 body 无 fs 不可用——文档标注 |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

- FormBody：构造期一次编码，请求期零额外分配（Bytes 直接进定长帧）。
- Multipart：段头 Bytes 预生成；文件段整块泵送——大文件上传内存上界 =
  发送缓冲 + fs 读缓冲。
- 进度包装每块一次回调、无分配。
- json[T]：`bytes()` 后解析（buffered 语义），非流式热路径。

## 测试方案

- US-1/2/3 基于 P03 夹具：捕获对端逐字节断言 + echo 回显比对（native+wasm
  双绿）。
- 大文件内存峰值：native 侧 RSS 观测（P06 门禁方法学对齐）。
- 进度：计数断言 + cancel 中断断言。
- json：roundtrip + 错误类型；charset 矩阵（utf-8/latin-1/缺省）。

## 澄清问题种子（clarify 输入）

- **C1** `@async/fs` stat/metadata 可用性（F4 前置待验证项；结论决定
  `file(path)` 是否强制显式长度）。
- **C2** json 依赖选型与版本（core 内建 vs moonbitlang/x；对 moon.mod 的
  依赖面影响）。
- **C3** charset 表范围（utf-8/latin-1 起步是否够；别名容错口径）。
- **C4** boundary 随机源（core/random 可用性 vs 自带 LCG + `@async.now()` 种子）。
- **C5** 下载进度 API 形状与上传对称性（ResponseBody::with_progress 命名与
  回调粒度）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. Multipart 逐字节线上形态断言 + >100MB 流式内存上界断言通过。
3. fs stat 验证结论（C1）写入 spec：取元数据或显式长度兜底，二选一有据。
4. F4/F5 回补完成可宣告（M1 明细状态更新就绪）。
5. `moon info && moon fmt` 干净；`.mbti` diff 已审视（新增构造器公开面）。

## 参考

- `09-request-bodies/README.md` §3.1–§3.4（实现方案）、§4（侵入性）、§6、§7、§8。
- M1 欠账 F4（`deferred-items/deferred-items-m1.md`）、F5；M1 差异 D5/D6。
- M1-P02（RequestBody/BodySource 与定长帧转换层）、M1-P01（percent 基础）、
  M1-P03（夹具）。
