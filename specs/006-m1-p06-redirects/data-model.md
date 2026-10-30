# Data Model: 自动重定向 follow-up 循环（M1-P06）

> Phase 1 产物。实体与不变量的机制级定义；行为语义见 spec FR，
> 证据见 research.md，公开面契约见 contracts/follow-up-api.md。

## 实体

### 实体 1：follow-up 循环（`Call::exchange_loop`）

组内子任务体的主循环（R2）。每轮结构：

```moonbit
while true {
  guard self.cancelled else raise CallCancelled        // FR-001（裸变体）
  ensure_lease(address_of_request(request))            // R6：同 host 复用（lease.addr 直读判定）/缺失 acquire
  errdefer poison_release()                            // P05 既有：轮内失败毒化
  let response = exchange_with_lease(request)          // 单轮管线（代次折叠 R3）
  match follow_up_request(response, request) {         // 实体 3 决策表（纯函数）
    Terminal => return with_prior(response, prior, keep_body=true)
    Next(followup) => {
      drain_intermediate(response)                     // R6：conn 上 skip（失败纯透传，毒化由轮级 errdefer 归属——D-2 注记）
      if self.conn_close_seen { release_lease() }      // FR-009（poisoned release=关闭）
      else if next_addr != lease.addr { release_lease() }  // 跨 host 干净回池（lease.addr 同包直读，D-4 订正）
      follow_ups += 1
      guard follow_ups <= 20 else { release_lease(); raise TooManyFollowUps }  // FR-005
      prior = Some(with_prior(response, prior, keep_body=false))
      request = followup
      self.gen += 1                                    // 实体 2 换代
    }
  }
}
```

与 5.5.0 RFU L93-120 循环的对应：`followUpRequest` ↔ 实体 3；
`response.body.closeQuietly()` ↔ `drain_intermediate`；
`++followUpCount > MAX` ↔ 计数 guard（排干之后、发送之前）；`if
(call.isCanceled())` ↔ 循环顶 guard。差异一处：moonhttp 的跨 host
换租在 advance 时显式 release（OkHttp 经 exchange 结束自然回池），
可观测语义相同（SC-003 断言面）。

**处置归属（round3 D-2 裁决钉死）**：轮级 `errdefer
poison_release()` 是轮内失败的**唯一毒化归属点**（exchange 段 P05
既有 errdefer 与之幂等叠合，无害）；`drain_intermediate` 内不写
catch/毒化，错误纯透传（R6 措辞按此口径读）。guard else 内
`release_lease()` 必须先于 `raise TooManyFollowUps`——该顺序是
INV-4「干净释放再 raise」的成立条件（反序将使 errdefer 把已排干
连接毒化关闭）；`release_lease`/`poison_release` 的 no-op 幂等为
承重细节，重构必须保留。红侧/断言文本中的 `poison_release` 字样均
指**可观测结果**（连接被毒化关闭、不回池），不指调用位点——读法
约定成文（round6 N-1，round8 落笔）。

> **P07 修正注记（2026-10-30，specs/007-m1-p07-stale-retry FR-007
> 承接）**：上段「唯一毒化归属点」的唯一性**限于错误逸出路径**——
> P07 轮内尝试子循环的重试路径，其毒化由捕获分支显式完成
> （`poison_release()` 先于 continue，007 INV-R1），错误不逸出、
> errdefer 不触发。逸出路径（不可重试 re-raise）归属不变；errdefer
> 登记点已随 007 上移至子循环之前（对 None lease 为 no-op，安全）。
> 机制形状见 007 data-model「子循环状态迁移」。

### 实体 2：follow-up 请求代次（generation）

代次 = call 内第 n 个待发送请求的序号（0 = 用户原请求）。承载：

- `Call.gen : Int32`——当前代次；仅在决定跟随后 +1（单调）。
- `Call.folded_gen : Int32` + `Call.folded : Map?` + `Call.fold_count
  : Int32`——L3 折叠缓存按代次键化（C4）：`folded_gen == gen` 时
  复用同一 Map 实例；换代后首次发送重折叠恰一次。同代次重放
  （P07 场景）零重折叠 ⇒ P05 SC-004 语义保持。
- 不变量 INV-3：`folded` 缓存有效 ⟺ `folded_gen == gen`；任何轮次
  发送的头必须来自当前代次折叠产物（FR-010 正确性下限）。

### 实体 3：决策表（`follow_up_request`，纯函数无 IO）

输入 `(response, request)`，输出 `Terminal | Next(Request)`。
真值表（5.5.0 对拍，R1）：

| 响应码 | Location | 方法 | body | 判定 |
| --- | --- | --- | --- | --- |
| 300/301/302 | 有 | GET/HEAD | — | Next（方法/头/体原样；跨 host 剥两头） |
| 300/301/302 | 有 | 其余（九法内非 GET/HEAD） | 任意 | Next：GET、无体、去 Content-Length/Content-Type/Transfer-Encoding（跨 host 剥两头） |
| 303 | 有 | GET/HEAD | — | Next（原样；跨 host 剥） |
| 303 | 有 | 其余 | 任意 | Next：GET、无体、去同上三头（跨 host 剥） |
| 307/308 | 有 | 任意 | Bytes/无 | Next：方法/体/头原样（跨 host 剥） |
| 307/308 | 有 | 任意 | Stream | **Terminal**（原样返回该响应，R1 第 5 条对齐 one-shot） |
| 300/301/302/303/307/308 | 无/非法（resolve raise） | — | — | Terminal |
| 304/305/306/401/407/408/其余 | — | — | — | Terminal |

- 「跨 host」= `Address(request.url) != Address(target)`（scheme/
  host/port 任一不同，R1 第 7 条）。
- Next 请求经 `RequestBuilder` 重组（R4），构建错误
  `HttpMessageError` 理论不可达、透传不吞。

### 实体 4：prior 链

`Response::prior` 单向链（P02 预留面，P06 填充）。构建（R5）：

- 条目 = `from_http(code, reason, headers.to_http_map(), cookies,
  body=None, prior=prev)`——**条目恒 body=None**（对齐 OkHttp）。
- 终态响应 = 原响应装配 `prior=链头`，活体透传。
- 不变量 INV-5：链长 = 实际发生跳数；顺序 = 跳进顺序
  （终态.prior = 倒数第 2 个响应，回溯首达最初 3xx）。

### 实体 5：TooManyFollowUps

client 包显式错误变体（R9）。触发条件（INV-4）：第 21 个「仍需
跟随」的响应被排干、旧租约干净释放后，于发送第 21 个 follow-up 前
raise；判别式 `err is TooManyFollowUps`；至多 20 个 follow-up 实际
发出（总请求 21）。

### 实体 6：Call 新增内部字段（全 priv，公开面零变化）

| 字段 | 类型 | 语义 | 不变量 |
| --- | --- | --- | --- |
| `gen` | `Int32` | 当前请求代次 | INV-3 关联；单调递增 |
| `folded_gen` | `Int32` | 折叠缓存所属代次 | INV-3 |
| `conn_close_seen` | `Bool` | 本轮响应已见 Connection: close（租约已被 poison） | INV-7：ensure_lease 取新租时复位 |

既有字段语义不变（`lease`/`folded`/`fold_count`/body 事件四标记）。
**不设 `lease_addr` 镜像字段**（round3 D-4 订正）：`Lease` 的
`priv addr` 同包直读（client.mbt:134-141；先例 exchange.mbt:98
直读 `lease.conn`），租约地址判定经 `lease.addr` 直读完成；`lease`
处置即置 None（INV-1），无需第二个可失同步的镜像状态面（宪法 VI）。

## 不变量汇总（INV-1..7）

- **INV-1**（租约守恒，承 P05 I-3）：`self.lease` 非 None ⟺ 当前
  轮的响应体可读/可排干；处置完成（release/poison_release）即置
  None；租约地址仅经 `lease.addr` 同包直读，无镜像字段。
- **INV-2**（排干前置）：任何 follow-up 请求的字节发出前，上一响应
  体必已完全排干（skip 返回）——连接状态机 clean state 要求（P05
  FR-005 前提在循环内的延伸）。
- **INV-3**（代次键化）：折叠缓存复用 ⟺ `folded_gen == gen`；发送
  头必为当前代次折叠产物。
- **INV-4**（上限计数）：计数在「响应到达 + follow-up 已算出」后、
  发送前推进；`follow_ups ≤ 20`；超限路径先排干后干净释放再 raise。
- **INV-5**（prior 链）：条目 body=None；链深 = 跳数；保序。
- **INV-6**（换租）：跨 host advance 必经「排干 → release_lease」，
  新租由下一轮 `ensure_lease` acquire；同 host advance 零租约往返。
- **INV-7**（close 中间响应）：`conn_close_seen` 置位 ⟹ 该轮
  advance 必 release（poisoned release = 关闭）；标记仅由
  `ensure_lease` 取新租复位。

## 状态迁移图

### 轮循环（宏）

```text
Pending ──execute──▶ [轮 k: guard cancel]
   cancel ──▶ CallCancelled（裸）
   决策表 Terminal ──▶ 终态响应(prior 链) ──▶ Delivered（P05 外壳不变）
   决策表 Next ──▶ 排干 ──▶ keep | swap | close-release ──▶ 计数检查
        超限 ──▶ release + TooManyFollowUps
        未超 ──▶ 换代 ──▶ [轮 k+1]
任意轮内错误/取消 ──▶ poison_release + 错误透传（P05 既有通道）
```

### 租约三态（每轮 advance 决策）

```text
             ┌─ conn_close_seen ──▶ release(poisoned)=关闭 ─┐
响应排干后 ──┤─ 跨 host ──────────▶ release(干净回池)      ├─▶ lease=None
             └─ 同 host ─────────▶ 保持（lease 不动）      ┘      │
                                                                 ▼
                                        下一轮 ensure_lease：None ⇒ acquire(addr)
                                                              Some∧addr同 ⇒ 复用
```

## 与 P05 既有实体的接面

- `exchange_once`/`exchange_with_lease`：仅参数化（request 入参），
  单轮管线步骤与毒化收尾零变化（R3）。
- `BodyBridge`：仅服务终态响应（中间响应不走 bridge——R6）；终态
  事件语义（Consumed/Dropped/Abandoned）零变化。
- 取消三通道：循环顶 guard 是标记通道的逐轮延伸；(b)(c) 通道原样。
- `HttpClient`/`ConnectionPool`/`Lease`/`Address` 公开面零变化。
