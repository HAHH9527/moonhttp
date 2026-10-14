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

**看什么**：US-1–US-4 验收场景与 15 条边界用例（spec Edge Cases）全部有
对应断言；关键锚点（[contracts/http-url.md](contracts/http-url.md)、
[contracts/headers.md](contracts/headers.md) 的「验收锚点」表）逐条通过：
规范化 `http://example.com/a/c?x=1#frag`、IPv6 剥括号、userinfo/端口/scheme
按变体报错、resolve 各形态（含 query-only、仅 fragment、base 无 path）、
HeadersV 折叠 `"a,b"` 与两个折叠不变量、往返幂等。

### 2. js 编译检查（宪法 V 降级线）

```text
moon check --target js      # 期望：无错误
```

### 3. 零警告门禁与接口冻结（SC-004，宪法 VI）

```text
moon check                  # 期望：零错误零警告（含 [0079]/[0027]）
moon info && moon fmt       # 期望：干净无 diff 残留
```

**看什么**：`src/core/pkg.generated.mbti` 的公开面 = 4 值类型（HttpUrl/
HeadersV/HeadersVBuilder/Method）+ 2 错误枚举（HttpUrlError/HeadersError）+
parse/resolve/to_string/访问器/get/values/add/set/remove/build/to_http_map
+ 各值类型 `pub extend` 暴露的 `equal`/`not_equal`/`hash`/`hash_combine`/
`to_repr` + 脱敏逃生口方法——**不得**出现自立 `Scheme` 枚举、包级掩码开关
或任何意外泄漏类型（决策 N2-A/N4-A）。

### 4. 敏感头零明文泄漏（SC-005，宪法「技术约束与合规」）

**看什么**：含 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie`
的 HeadersV 实例，其调试输出不含对应明文头值；`git grep` 在 `src/core` 的
`.snap` 快照与测试期望串中查不到这些明文样例值；测试代码未调用逃生口方法
（FR-013）。

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
- wasm-gc：不支持（research R7）；js 运行时行为：仅编译检查（D9）。
- 网络 IO：本包无（FR-011）；网络行为验证属 P02+ 包。
