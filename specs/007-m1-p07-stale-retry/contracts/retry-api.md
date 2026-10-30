# Contracts: 连接失败重试 stale-retry（M1-P07）

> 2026-10-30。对账面：spec FR-011 冻结面、SC-008。基线＝005 FR-014
> 与 006 FR-012 冻结面叠加。

## §1 client 公开面增量（唯一）

`src/client/pkg.generated.mbti` 变更恰为以下一项：

```text
- pub fn HttpClient::new(ConnectionPool) -> HttpClient
+ pub fn HttpClient::new(ConnectionPool, retry_on_connection_failure? : Bool) -> HttpClient
```

- 缺省 true（OkHttp 默认行为面）；false ⇒ 判定器恒 Fail（任何失败
  不重试，毒化等既有语义不变）。
- **零新增**：错误变体（错误面与 P05/P06 既有集合一致，透传原始错
  误值——FR-008）；公开方法；`stale_evictions` 写入口（读访问器
  已在 004 公开，写入口保持私有——FR-004/FR-011）。
- core 包 `.mbti` 零 diff；fixtures 包 `.mbti` 增量见 §3（内部包，
  不属 client 冻结面对账范围）。

## §2 priv 接缝契约（包内可见，非公开面）

```text
priv enum SendStage     { Connect; Send; ReadHead }        # recover.mbt（全 target）
priv enum ErrFamily     { Stale; Protocol; ConnectFailure; Other }
priv enum RetryDecision { Retry; Fail }

priv fn error_family(stage : SendStage, err : Error) -> ErrFamily
  # recover_family.mbt〔moon.pkg options(targets) 显式锁 native,wasm——
  #   普通命名文件默认全 target，必须声明（qod-2 必修⑥）〕
  # recover_family.js.mbt〔.js.mbt 后缀自动锁 js〕：恒 Other（重试不激活）
priv fn decide(stage : SendStage, family : ErrFamily,
               body : @core.BodySource?, stream_body_entered : Bool,
               attempts : Int, enabled : Bool, cancelled : Bool) -> RetryDecision
  # recover.mbt（全 target 共享纯函数）；矩阵见 data-model 实体 3
  # （含 replayable 前置门与收尾兜底行）

priv fn ConnectionPool::note_stale_hit(self) -> Unit
  # 锁内 stale_evictions += 1；调用判据＝decide==Retry ∧ stage==ReadHead
  # ∧ family==Stale，调用点仅一（exchange 段捕获分支 poison_release 后）

# Call priv 字段：last_stage : SendStage / stream_body_entered : Bool
#   （子循环体首行复位；开关不复制进 Call——判定处直读 client priv 字段）
# HttpClient priv 字段：retry_on_connection_failure : Bool
```

职责边界：
- `exchange_with_lease` 签名与逸出行为零变化（阶段标记为调用点前置
  赋值插桩）。
- `exchange_loop` 轮结构、`follow_ups` 计数、决策表、prior 链、
  `advance_generation` 调用点零变化（尝试子循环为轮内新增）。
- 轮级 errdefer 单点登记**上移至取消 guard 之后、子循环之前**
  （qod-2 必修⑤；对 None lease 为 no-op 故提前登记安全）；捕获分
  支次序统一 `family → decide → Retry{poison_release() →
  (ReadHead∧Stale) note_stale_hit() → continue} / Fail{raise}`。
- 逸出路径毒化归属＝轮级 errdefer（006 D-2 加注后的措辞：唯一性限
  于错误逸出路径）；重试路径毒化＝捕获分支显式 `poison_release()`，
  必须先于 continue（INV-R1）。

## §3 fixtures 增量（内部测试基建；qod-2 必修⑦修订：比选后扩面）

**优先路径（零公开面增量）**：现有 `Capture` 变体 + 同一 ScriptedPeer
实例串行 `run()` 两次（监听 socket 在 run 返回后仍打开，close 在
raw_peer.mbt:447）——conn1 serve→close（静默关闭）、conn2 承接重试
新连接；每 run 各返一份 `CapturedRequest`，双连接捕获返回面天然成
立。**前置探针**：Capture canned 200 必须带 Content-Length 且无
`Connection` 头。

**后备路径（仅探针不合时）**：新增 PeerProgram 变体
`SilentCloseThenServe`（conn1：读尽请求帧→200 + `Content-Length: 0`
无 Connection 头→静默 close；conn2：正常 serve），返回面同构（每
run 一份 CapturedRequest），计入本包 fixtures `.mbti` 增量（internal
包，不属 client 冻结面对账范围）。

**编排约束（两路径通用）**：(a) 两次 run 与两次 execute 全程测试内
串行（夹具 accept 串行契约，raw_peer.mbt:16-18）；(b) `timeout_ms`
缺省 5000ms 信封显式放宽；(c) 预热 execute 必须读尽响应体（或 skip
收尾）使租约回池；(d) 断言集合＝双捕获逐字节一致（SC-004）+
stale_evictions==1 + accepted_total==2 + 池计数守恒。

## §4 跨文档修订义务（implement 同批）

| 文档 | 修订 |
| --- | --- |
| specs/006-m1-p06-redirects/data-model.md | D-2 行加注：errdefer 唯一毒化归属点**限于错误逸出路径**（P07 修正，2026-10-30） |
| src/client/codemap.md | 订正「两错误变体」漂移（实况三变体）+ 补 recover.mbt/recover.js.mbt 职责行 |
| docs/roadmap/M1/P07-stale-retry.md | 已于 spec 提交批完成两处裁决回写（R2/C4 注记） |

## §5 moon.pkg 变更

`src/client/moon.pkg`：
1. 常规 import 增 `moonbitlang/async/os_error`、
   `moonbitlang/async/tls`、`moonbitlang/async/socket`（js 上三包为
   空包；`unused_package` 警告已由本包既有包级抑制
   `warnings: "-unused_package"` 覆盖，无需追加）。
2. **新增 `options(targets: ...)` 表**：`recover_family.mbt` 锁
   `[native, wasm]`（承载锁定类型引用；普通命名文件默认全 target，
   必须显式声明——qod-2 必修⑥，上游 http/moon.pkg:60-61
   client.mbt/client.js.mbt 成对声明先例）；`recover_family.js.mbt`
   由后缀自动锁 js。
3. **js 验收口径（T0 基线实测 2026-10-30）**：`moon check --target js`
   基线即红（13 个既有错误，`@http.ServerConnection` 等上游 js 缺
   口）——P07 过门条件＝与基线错误集 diff **零新增错误**。
