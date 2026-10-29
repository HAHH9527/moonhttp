# Quickstart: 自动重定向 follow-up 循环（M1-P06）验证指南

> 六门跑法与分场景验收命令；机制与契约见
> [data-model.md](data-model.md) / [contracts/follow-up-api.md](contracts/follow-up-api.md)。
> 本包验证全部基于 P03 本地夹具（loopback），断网可跑（SC-007）。

## 合入前六门（宪法「开发工作流与质量门」）

```bash
moon info && moon fmt                 # 门1：接口与格式干净；.mbti diff 对账 contracts/follow-up-api.md
moon test --target native             # 门2：native 全绿
moon test --target wasm               # 门3：wasm 全绿
moon check --target js                # 门4：js 编译检查（非门禁，仅不回退编译面）
moon coverage analyze > uncovered.log # 门5（辅助）：决策表分支覆盖人工复核
# 门6：宪法合规自查（spec 映射表四处显式差异在场；本表即记录载体）
```

`.mbti` 期望 diff：client 仅增 `TooManyFollowUps` 两件套；core/fixtures
零 diff（contracts §1/§2/§3 对账，SC-008）。

## 分场景验收（US ↔ 命令）

全部场景经 `moon test` 内元测试承载（映射表 research R10），无需独立
脚本；按下表过滤运行可单独复核：

```bash
# US-1 方法降级跟随（POST/PUT/DELETE 降级、HEAD 保持、prior 链）
moon test --target native -p hahh9527/moonhttp/client -f call_test.mbt
# US-2/US-3/US-4/US-5/US-6 场景与白盒面同包运行：
moon test --target native -p hahh9527/moonhttp/client
```

场景要点（判据细则见 spec 各 US 的 Acceptance Scenarios）：

1. **US-1**：POST/PUT/DELETE × 300/301/302/303 → GET 降级、无体与
   Content-Length/Content-Type 头；HEAD 全码保持；prior 链深 = 跳数。
2. **US-2**：307/308 + Bytes 逐字节重放（对端两次捕获一致）；Stream
   原样返回该 3xx。
3. **US-3**：相对/绝对/网络路径 Location 正确 resolve 后跟随；缺失/
   非法 → 原 3xx 终态。
4. **US-4**：跨 host follow-up 字节不含 `Authorization`/`Cookie`
   （ScriptedPeer Capture）；同 host 保留。
5. **US-5**：21 跳链与 A→B→A 循环 → `err is TooManyFollowUps`；
   304/305/306、无 Location 的 300 → 终态透传。
6. **US-6**：3 跳同 host 链连接数 = 1、终态后同连接下个请求干净流；
   跨 host 跳新连接 +1；中间 `Connection: close` → 后续新连接。

## js 非门禁项（宪法 V，欠账随 M5 收口）

- js 形态：`@http` fetch 适配层浏览器自动跟随 ⇒ 循环首轮即终态、
  `prior` 不可用（research R8；spec FR-011/target 矩阵）。
- 仅 `moon check --target js`；无 node 冒烟要求（P05 同口径延续）。
