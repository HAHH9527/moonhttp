# 09 请求体构造（FormBody / MultipartBody / 流式 / 上传进度 / 响应便捷解析）

> 结论：**非侵入可实现**。async/http 的 body 模型（`&@io.Data` + Writer 流式）完全够用，缺的只是构造器与便捷层。

## 1. OkHttp 行为规格（Recipes 面）

- POST String / 流式 body（Okio BufferedSink/OutputStream）/ 文件 body。
- `FormBody.Builder`：`application/x-www-form-urlencoded`，键值 percent-encode，Content-Length 已知。
- `MultipartBody.Builder`：`multipart/form-data`，多 part（字符串/文件/自定义），boundary 自动生成。
- Moshi 集成 JSON；`ResponseBody.charStream()` 按 Content-Type 选字符集（默认 UTF-8）。
- 上传进度：包装 RequestBody + ForwardingSink。

## 2. async/http 现状（证据）

- body 类型：`&@io.Data`（String/Bytes/View/Json 统一转换 trait，`io/mbti:69`）+ `Client` 作 `@io.Writer` 流式写（`client.mbt:196-208`）；`write_reader` 支持从任意 Reader 泵入（`send.mbt:176-243`）。
- **全无** form/multipart/进度（既有对比研究 §3.2）。
- 定长帧机制：已知长度走 `extra_headers~{"Content-Length": n}` → `SendingFixed`（`send.mbt:292-309`；round3 实测）——构造器层的核心任务是**总是给出 Content-Length**。
- gzip：`@gzip.Encoder`（flush/end，`gzip/mbti:24-32`）可用于请求体压缩拦截器（04 §3.4）。
- 文件读取：`@async/fs`（http 测试已依赖，`moon.pkg` test imports）。
- 随机源：boundary 生成需要（core 的 random 包或自带 LCG，见 §3.2）。

## 3. 实现方案

### 3.1 FormBody

```moonbit
pub struct FormBody { encoded : Bytes }   // 构造期一次性编码完成
pub fn FormBody::Builder() -> FormBuilder
pub fn FormBuilder::add(name : String, value : String) -> FormBuilder
pub fn FormBuilder::add_encoded(name : String, value : String) -> FormBuilder   // okhttp 同名：跳过编码
pub fn FormBuilder::build() -> RequestBody   // content_type="application/x-www-form-urlencoded",
                                             // content_length=encoded.length()（已知 → 定长帧）
```

- percent-encode 规则对齐 okhttp FormBody：保留 `*`、`-`、`.`、`_`，空格→`+`（application/x-www-form-urlencoded 语义），其余非 [A-Za-z0-9] 编码为 `%XX`——~30 行，自写（core 若有 `encoding/url` 直接用）。

### 3.2 MultipartBody

```moonbit
pub struct MultipartBody {
  boundary : String
  content_type : String                  // mixed / form-data / related / alternative
  parts : Array[Part]
}
pub fn MultipartBody::Builder() -> MultipartBuilder   // setType/addFormDataPart/addPart
// addFormData_part(name, filename?, RequestBody)  → form-data 段（Content-Disposition）
// 序列化：惰性流式拼装（见下），总长可预先计算（各段 headers+body 长度全已知，文件段用文件大小）
```

- **boundary 生成**：`长度 32 的随机 hex`；随机源取 `moonbitlang/core/random`（若无则自带 xoshiro/PCG ~40 行，种子用 `@async.now()`——注意仅供 boundary 唯一性，非密码学；文档说明）。追加保险：boundary 内嵌 `moonbit-multipart-` 前缀降低正文碰撞概率（okhttp 同思路）。
- **流式拼装（大文件上传不进内存）**：MultipartBody 转成 `BodySource::Stream`，但**总 Content-Length 预先可算**（文件段长度来自 fs 元数据）→ 走定长帧：段头 Bytes 直接 `client.write`，文件段 `client.write_reader(FileReader)`（`write_reader` 的 `SendingFixed` 分支已优化为整块泵送，`send.mbt:188-205`）。这兼顾"零内存膨胀 + 定长帧"。
- 收尾 `--boundary--\r\n` 计入总长。

### 3.3 文件与流式 body（01 §3.3 的补全）

- `RequestBody::file(path)`：`@async/fs` 打开；content_length 来自 stat（fs 接口需确认有 metadata；若无可先读尾或要求显式传长度——**待验证项**，列入实现前置检查）。
- `RequestBody::writer(content_length?, f : async (&Writer) -> Unit)`：一次性回调式流（不可重放，02 §3.3 语义：已写出字节后不可重试）。
- 进度：`RequestBody::with_progress(body, on_increment : Int64 -> Unit)`——Bytes 分 32KB 块写、每块回调；Stream/文件在 write_reader 外围包计数 Writer（实现 `@io.Writer::write_once` 计数后透传）。对齐 okhttp ForwardingSink recipe。

### 3.4 响应侧便捷

- `ResponseBody::text()` 按 `Content-Type` 的 charset 参数选解码（默认 UTF-8）——01 §3.6 已列；charset 表至少 utf-8/latin-1（core `encoding/utf8` 已依赖）。
- `ResponseBody::json[T : FromJson]`（泛型收发，derive 在语言层）：`bytes() → parse`；对齐 okhttp+Moshi recipe。错误包装 `JsonDecodeError`。
- 下载进度：`ResponseBody::with_progress` 同形。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 全部构造器/进度/便捷解析 | **非侵入** | 纯上层 |
| fs 元数据（文件长度） | 待验证 | `@async/fs` 是否有 stat/metadata；若无：【侵入 async/fs，~20 行】或 M1 要求显式长度 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | wasm 的 fs 走宿主注入（16） |
| js | ⚠️ | fetch 路径：FormBody/MultipartBody/进度可用（body 一次性传给 fetch）；**流式上传**（writer body）需缓冲成完整 Bytes 再 fetch（`client.js.mbt:132-139` 本就缓冲）——文档标注；文件 body 无 fs |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- FormBody 构造期一次编码、请求期零额外分配（Bytes 直接进定长帧）。
- Multipart 流式：段间头 Bytes 预生成；文件段 `write_reader` 直通 Sender 的整块泵送（`send.mbt:188-205` 的 `SendingFixed` 循环）——上传大文件内存上界 = 1KB send_buf + fs 读缓冲。
- 进度包装每块一次回调，无分配（计数器传 Int64）。

## 7. 工作量与依赖

- 依赖：01（RequestBody/BodySource）。
- 估计：FormBody ~0.5 人日；Multipart ~1.5；进度/文件 ~1；响应便捷 ~0.5；测试 ~1.5。**~5 人日**。

## 8. 测试方案

- FormBody：编码矩阵（空格/中文/保留字符/预编码）+ 服务端回显比对。
- Multipart：多段（文本/二进制/文件）经本地夹具收包逐字节断言 boundary/CRLF/终结段；大文件（>100MB）上传内存峰值断言（流式不膨胀）；boundary 正文碰撞构造用例。
- 进度：总字节数与回调次数、取消中途停止。
- json[T]：roundtrip + 错误类型。
