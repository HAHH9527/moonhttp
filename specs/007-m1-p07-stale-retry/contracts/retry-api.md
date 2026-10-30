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
priv enum SendStage     { Connect; Send; ReadHead }
priv enum ErrFamily     { Stale; Protocol; ConnectFailure; Other }
priv enum RetryDecision { Retry; Fail }

priv fn error_family(err : Error) -> ErrFamily
  # recover.mbt [native, wasm]：全量分类
  # recover.js.mbt [js]：恒 Other（重试不激活，Target 矩阵）
priv fn decide(stage : SendStage, family : ErrFamily,
               body : @core.BodySource?, stream_body_entered : Bool,
               attempts : Int, enabled : Bool, cancelled : Bool) -> RetryDecision
  # 全 target 共享纯函数；矩阵见 data-model 实体 3

priv fn ConnectionPool::note_stale_hit(self) -> Unit
  # 锁内 stale_evictions += 1；调用点仅「Stale ∧ ReadHead 进入重试分支」

# Call priv 字段：retry_enabled : Bool / last_stage : SendStage / stream_body_entered : Bool
# HttpClient priv 字段：retry_on_connection_failure : Bool（new_call 装入 Call）
```

职责边界：
- `exchange_with_lease` 签名与逸出行为零变化（阶段标记为调用点前置
  赋值插桩）。
- `exchange_loop` 轮结构、`follow_ups` 计数、决策表、prior 链、
  `advance_generation` 调用点零变化（尝试子循环为轮内新增）。
- 逸出路径毒化归属＝轮级 errdefer（006 D-2 加注后的措辞：唯一性限
  于错误逸出路径）；重试路径毒化＝捕获分支显式 `poison_release()`，
  且必须先于 continue（INV-R1）。

## §3 fixtures 包增量（内部测试基建）

`src/internal/fixtures`（PeerProgram 变体，命名 implement 定）：

```text
+ <SilentCloseThenServe>   # 同端口两连接顺序处理：
                           #  conn1: 读尽请求帧 → 200 + Content-Length（无 Connection 头）→ 静默 close
                           #  conn2: 正常 serve（canned 200）
```

- 与 B-06 的关键差异：不带 `Connection: close`（否则客户端主动毒
  化，不构成陈旧场景）。
- drain 内置（先读尽请求帧再 close ⇒ FIN 确定性，D12 教训继承，
  不加公开枚举字段）。
- `.mbti` 入公开面（fixtures 为 `internal` 包，消费方仅本仓测试域）。

## §4 跨文档修订义务（implement 同批）

| 文档 | 修订 |
| --- | --- |
| specs/006-m1-p06-redirects/data-model.md | D-2 行加注：errdefer 唯一毒化归属点**限于错误逸出路径**（P07 修正，2026-10-30） |
| src/client/codemap.md | 订正「两错误变体」漂移（实况三变体）+ 补 recover.mbt/recover.js.mbt 职责行 |
| docs/roadmap/M1/P07-stale-retry.md | 已于 spec 提交批完成两处裁决回写（R2/C4 注记） |

## §5 moon.pkg 变更

`src/client/moon.pkg` 常规 import 增：
`moonbitlang/async/os_error`、`moonbitlang/async/tls`、
`moonbitlang/async/socket`（js 上三包为空包，判定器 js 文件无引用
点；unused_package 警告若现于 js check，如实记录不抑制——js 非门禁）。
