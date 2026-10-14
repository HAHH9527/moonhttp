# Quickstart：验证 core 值对象可用（M1-P01）

**目的**：不改一行实现的前提下，证明本特性端到端可用——所有验证都经
`moon test` / `moon check` 完成（纯值对象无运行入口，测试即验收载体）。

## 前置条件

1. 工具链：`moon version` ≥ 0.1.20260920。
2. `moon.mod` 已声明 `import "moonbitlang/async@0.22.4"`（本包任务 1 产出；
   见 [research.md](research.md) R1）。
3. `src/core` 包存在且 `moon.pkg` 已 import `moonbitlang/async/http`
   （import 键写包目录路径，`@` 只在代码引用处作命名空间，见
   [research.md](research.md) R10）。

## 验证步骤

### 1. 双 target 测试（核心验收，SC-001）

```text
moon test --target native   # 期望：全绿
moon test --target wasm     # 期望：全绿
```

**看什么**：US-1–US-4 验收场景与 14 条边界用例（spec Edge Cases）全部有
对应断言；关键锚点（[contracts/http-url.md](contracts/http-url.md)、
[contracts/headers.md](contracts/headers.md) 的「验收锚点」表）逐条通过：
规范化 `http://example.com/a/c?x=1#frag`、IPv6 剥括号、userinfo/端口/scheme
按变体报错、resolve 各形态（含 query-only、仅 fragment、base 无 path）、
HeadersV 折叠 `"a,b"` 与两个折叠不变量、往返幂等。

### 2. 验证面口径核对（SC-004，宪法 v1.2.0 原则 V :67-77）

验证面为 **native 与 wasm**（步骤 1 的双 target 测试 + 步骤 3 的 check 零
错误零警告）；js 与 wasm-gc 显式标注「暂不验证」并挂欠账跟踪（F9，M5
target 收口；合入质量门 :130-133 不作本包门禁）——**不执行**
`moon check --target js` / `--target wasm-gc`（M1 阶段无有效信号，wasm-gc
因 @http 编译图为编译失败而非警告）。

### 3. 零警告门禁与接口冻结（SC-004，宪法 VI）

```text
moon check                  # 期望：零错误零警告（含 [0079]/[0027]）
moon info && moon fmt       # 期望：干净无 diff 残留
```

**看什么**：`src/core/pkg.generated.mbti` 的公开面 = 4 值类型（HttpUrl/
HeadersV/HeadersVBuilder/Method）+ 2 错误枚举（HttpUrlError/HeadersError）+
parse/resolve/to_string/访问器/get/values/add/set/remove/build/to_http_map
+ **Builder 双入口**（`HeadersVBuilder::new()` 造空、`HeadersV::builder()`
回转不重跑 FR-012 校验，R2-C1）+ 各值类型 `pub extend` 暴露的 `equal`/
`not_equal`/`hash`/`hash_combine`/`to_repr`——**不得**出现自立 `Scheme`
枚举、Logger/`Show`/`to_display`/序列化输出类签名、`debug_unredacted` 类
逃生口或任何意外泄漏类型（决策 N2-A/R3-H1-A/R3-M3-A；全部公开类型为
`derive(Debug)` 默认实现）。

### 4. 输出面三项核对（SC-005，宪法 v1.2.0 :112-117）

**看什么**：① `.mbti` 无 Logger / `Show` / `to_display` / 序列化输出类签名
（全部公开类型 `derive(Debug)` 默认实现，R3-H1-A）；② 错误消息只携带定位
片段、不整体回显原始输入；③ `HttpUrl::to_string` 不输出 userinfo（FR-008
结构性保证）。另抽查（R3-M1 纪律）：测试与 `.snap` 中的敏感头样例值为
合成占位串（如 `Bearer test-token-123`），`git grep` 不得出现真实形态
凭证串。

### 5. OkHttp 移植对拍清单（SC-002，宪法 III/IV）

**看什么**：测试文档（或测试文件头注释）列明移植组（畸形输入/规范化/
resolve/IPv6/percent-encoding）与略去组（IDN、userinfo——M1 显式拒绝，
理由见 [research.md](research.md) R9），来源注明
`OkHttp 5.5.0 HttpUrlTest (Apache-2.0)`。

## 通过判据

上述 5 步全部符合期望 → P01 包级 DoD 达成（spec SC-001–SC-005），可进入
P02（Request/Response/体模型，复用本包冻结的 `.mbti` 接口）。

## 已知不验证项（显式排除）

- 性能基准：本包无门禁（P10 汇总覆盖，宪法 II）。
- js 与 wasm-gc：暂不验证（宪法 v1.2.0 原则 V :67-77；research R7/R15；
  M5 收口，欠账 F9）。
- 网络 IO：本包无（FR-011）；网络行为验证属 P02+ 包。
