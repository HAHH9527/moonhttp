# 契约：Response / ResponseBody（M1-P02 core 包公开 API）

**包**：`hahh9527/moonhttp/core`（P02 增量）。类型清单规范源：
[data-model.md §3/§4/§6](../data-model.md)。

## Response（不可变值 + 纯重建函数）

```moonbit
pub struct Response {
  code    : Int
  reason  : String
  headers : HeadersV                 // 由 @http 响应 Map 重建
  cookies : Array[@http.Cookie]      // 上游透传
  body    : ResponseBody?
  prior   : Response?                // 字段就位，P06 填充
} derive(Debug)

pub fn Response::from_http(code : Int, reason : String,
                           headers : @http.Headers,
                           cookies : Array[@http.Cookie],
                           body? : ResponseBody?, prior? : Response?) -> Response
```

**契约条款**：

1. `from_http` 为**纯函数**（无 IO）：headers 重建 = 逐键把逗号合并值以
   无空格 `,` 拆回多条（与 P01 折叠互逆，P01 SC-003 不变量②），条目序 =
   Map 遍历序；**顺序不保真，验收 MUST NOT 断言线上序**（FR-008，research
   R3/R7）。quoted-string 逗号不做边界感知（与 P01 同一已记录限制，认证
   路径 M2 绕过）。
2. `body`/`prior` 为可选装配位：`@http.Response` 无 body 字段，body 由
   P05 围绕 `Client as @io.Reader` 组装后传入；prior 由 P06 填充，本包不
   产生响应链。
3. cookies 仅透传（M1 不建 Jar）；js target 恒空（spec A8）。
4. 六要素访问器（`code()/reason()/headers()/cookies()/body()/prior()`）
   属公开面，随 `.mbti` 冻结审视。

## ResponseBody（buffered / stream 两态 + 生命周期）

```moonbit
pub struct ResponseBody { /* 两态内部 + 状态标志 + 事件回调 */ }
  // Debug 手写：印状态与元信息，不印 body 字节/reader 内部（research R10）

pub fn ResponseBody::buffered(data : Bytes) -> ResponseBody
pub fn ResponseBody::stream(reader : &@io.Reader,
                            on_event? : (ResponseBodyEvent) -> Unit) -> ResponseBody

pub async fn ResponseBody::bytes(Self) -> Bytes raise @io.Error   // buffered 直取；stream 读到底
pub async fn ResponseBody::text(Self) -> String raise @io.Error   // charset 集外降级 UTF-8（裁决 B，不 raise HttpMessageError）
pub async fn ResponseBody::read_some(Self, max_len? : Int) -> Bytes? raise @io.Error
pub fn ResponseBody::drop(Self) -> Unit                      // 幂等；未 consumed 时触发 Dropped
pub fn ResponseBody::consumed(Self) -> Bool
pub fn ResponseBody::dropped(Self) -> Bool
```

**契约条款**：

1. **buffered 态**：`bytes()` 直接返回完整负载；0 字节返回空、不报错。
2. **stream 态**：读取 API（`bytes()`/`text()`/`read_some`）统一
   `pub async fn` 口径——stream 态读 `&@io.Reader` 走上游 async 读取面，
   buffered 态同签名对齐（plan review 修订）。
   `bytes()` = 读到底（置 consumed、触发 `Consumed`）；
   `read_some` 增量读（`None` = EOF，EOF 同样置 consumed/触发事件）；
   `drop()` 幂等（已 consumed 时静默无事件）。事件触发契约与互斥/时序
   不变量见 [data-model.md §4 状态机](../data-model.md)：
   `Consumed`/`Dropped` 至多其一，`Abandoned` 仅由 P04/P05 所有者在收尾
   按 `consumed()/dropped()` 查询结果触发；默认回调 no-op（FR-006）。
   测试桩：`@io.MemoryReader` / `@io.pipe`（research R3）。
3. **charset（`text()`）**：解码集 M1 仅 {UTF-8}（**2026-10-16 owner
   裁决 B 覆写**）。解析规则（research R5）：取 `Content-Type` 合并值中
   首个 `charset=` 参数，名值大小写不敏感、值可带引号；缺省/`utf-8` →
   UTF-8；**其余任何 charset 值 → 按 UTF-8 降级解码（`@utf8.decode_lossy`，
   畸形序列替换 U+FFFD）并输出一条 stderr 告警，MUST NOT raise**——
   降级语义对齐 OkHttp 5.5.0（MediaType.kt:44-51 解析失败回退默认 +
   ResponseBody.string() 按 UTF_8）；stderr 告警为本地化增强（OkHttp
   静默），登记为可观测面有意差异（宪法 III），不改变返回值；告警唯一
   出口 = 包内私有 `warn_charset_fallback`，消息只带 charset 名定位
   片段。`text()` = `bytes()` + 解码（stream 态先触发 `Consumed`）。
4. **长度语义 = 解压后长度**（FR-010）：上游已透明 gzip（research R3），
   本包不重复处理、不感知 Content-Encoding。
5. `bytes()/read_some/text()` 的 IO 错误沿上游 raise 面（`@io.Error`）
   透传；charset 维度不产生错误（集外降级 UTF-8 + stderr 告警，
   2026-10-16 裁决 B），FR-012 自持错误类型仅覆盖方法/体矩阵与体长度
   两类违例。

**验收锚点**（spec US-3、US-4、Edge Cases、SC-002/003）：

| Given | When | Then |
| --- | --- | --- |
| 小缓冲响应 | bytes()/text() | 完整负载；UTF-8 正确解码 |
| Content-Type: charset=utf-8（任意大小写/引号） | text() | 按 UTF-8 解码 |
| charset=gbk（集外） | text() | 返回 UTF-8 lossy 解码结果（不抛错）+ stderr 告警（裁决 B） |
| 同一 gbk 声明 | text() 返回值 | == `@utf8.decode_lossy(原始字节)`；bytes()/consumed 状态机不受影响（裁决 B 补锚） |
| 无 Content-Type | text() | 按 UTF-8 解码 |
| 畸形 UTF-8 字节 | text() | U+FFFD 替换、不抛 |
| 0 字节响应 | bytes() | 空数据、不报错 |
| 流式体读到底 | 读取 | 触发 `Consumed`（可归池语义） |
| 流式体未读完即 drop | drop() | 触发 `Dropped`；幂等无重复事件 |
| consumed()==false 且 dropped()==false | P05 收尾查询 | 所有者触发 `Abandoned` |
| 逗号合并值重建 | from_http | 与 P01 折叠互逆；条目序 = 遍历序 |
