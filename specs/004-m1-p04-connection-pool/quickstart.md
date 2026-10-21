# Quickstart：P04 连接池验证指南

> 前置：仓库根 `moon.mod`（依赖 `moonbitlang/async@0.22.x`，registry 版本，
> 宪法技术约束）；moon ≥ 0.1.20261012（003 research P-h 核证）。
> 池宿主 `src/client`；夹具扩展 `src/internal/fixtures`（R5）。

## 0. 「-p 假验证」警示（先读）

`moon test -p` **只认包名**（形如 `hahh9527/moonhttp/client`）。写成目录
路径（如 `-p src/client`）会**跑 0 个测试却返回 exit 0**——假绿。每条
`-p` 命令执行后检查输出 `Total tests:` 必须非 0。

## 1. 收口六门（合入前逐条跑，全部通过才算交付）

```powershell
# 缓存命中不算重跑：最终收口轮先 moon clean；日常轮可增量
moon clean
moon check --target native --deny-warn   # 门 1
moon check --target wasm   --deny-warn   # 门 2
moon test  --target native --deny-warn   # 门 3（默认套：长跑条目 #skip 不计数，裁决 C5）
moon test  --target wasm   --deny-warn   # 门 4（同上）
moon fmt --check                          # 门 5
moon info                                 # 门 6：审 .mbti diff——
# 期望：src/core/pkg.generated.mbti 零 diff（P04 不改 core）；
#       src/client/pkg.generated.mbti ＝ contracts/pool-api.md §1 冻结面；
#       src/internal/fixtures 增面逐处归因（contracts §1 表，T025 先例）
```

分包等价命令（`-p` 全包名；与门 3/4 等价、用于定位失败）：

```powershell
moon test -p hahh9527/moonhttp/client            --target native --deny-warn
moon test -p hahh9527/moonhttp/internal/fixtures --target native --deny-warn
# --target wasm 各再跑一轮（双绿门）
```

## 2. 分场景验证（对应 spec US-1～US-4）

```powershell
# US1①–③ 租借归还 / US2① 并发串号 / US3①–② 驱逐与 evict_all /
# US4①–④ 毒化路径（共 10 条：US2① 在 pool_wbtest.mbt 白盒——改派
# 注记 R9：Lease.conn priv 黑盒不可达，`-f "P04-US2*"` 按测试名跨文件
# 收集、glob 语义不变；其余 9 条全在 pool_test.mbt 黑盒；P03 夹具 +
# @http.Client 原语独立驱动，不经 P05）：
moon test -p hahh9527/moonhttp/client -f "P04-US*" --target native
# US2① 单独跑（K=8 并发 100 请求串号检测）：
moon test -p hahh9527/moonhttp/client -f "P04-US2*" --target native
# E①–⑤ Address 键隔离/规范化（FR-014，address_test）＋ E⑥ acquire
# 失败透传（FR-015：黑盒 pool_test 透传/计数 ＋ 白盒 pool_wbtest 三集
# 合零变化，同名跨文件）＋ E⑦ 零空转护栏（D15，pool_wbtest）：
moon test -p hahh9527/moonhttp/client -f "P04-E*"   --target native
# 白盒（pool_wbtest）：FR①② 时钟注入/构造校验、FR③ 独占/守恒、
# FR④ 终结幂等、FR⑤⑥ 超期剔除、FR⑦ 计数口径、FR⑧ LIFO 次序：
moon test -p hahh9527/moonhttp/client -f "P04-FR*"  --target native
# 夹具扩展自证（FIX①②③：F-5/F-6/F-7 计数与次序脚本）：
moon test -p hahh9527/moonhttp/internal/fixtures -f "P04-FIX*" --target native
```

每条把 `--target native` 换成 `--target wasm` 再跑一轮（双绿门）。

## 3. 长跑/无泄漏双证据（US-2 场景 2；默认排除六门，裁决 C5）

长跑用例声明 `#skip` 属性：默认 `moon test` 不计数、不执行；显式执行经
`--include-skipped`（主案已核证：2026-10-20 host 实测，双 target、含
无属性对照组，见 research R8）。

```powershell
moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
  --include-skipped --target native
moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
  --include-skipped --target wasm
```

- 执行后核对 `Total tests:` 非 0（防 `-p` 写成目录路径的假绿，见 §0）。
- 禁止以 `#cfg` 充当跳过：条件编译会让测试从编译单元整个消失，
  `--include-skipped` 救不回来（2026-10-20 实测反例，research R8）。

- 断言口径（Q04 双证据）：外部——`accepted_total() == 池内累计新建`
  （白盒 `next_conn_id - 1`）；内部——`借出 + 空闲 + 已关 = 累计新建`
  （白盒三集合基数，data-model 不变量 5）。
- 规模分档：native ≥10k 请求；wasm/moonrun 按 t004-record.md 实测吞吐
  降额（implement 期校准）。通过证据登记进包级 DoD-1（spec 口径）。

## 4. 时钟注入说明（US-3 场景 1）

超期判定走注入时钟（research R2）：白盒测试用私有构造入口换受控时钟，
推进虚拟时间零 sleep。黑盒侧不直接测「到期」——到期能力由白盒用例
承载（同包 `_wbtest.mbt`，`moon test -p` 覆盖）。

## 5. 收尾对账

- `.mbti` diff 审视结论 + 六门输出摘要随交付汇报（宪法开发工作流节）。
- DoD-2 对账：FR/US ↔ 元测试映射表见 plan.md「映射表」节。
- 风险盯防三处见 plan.md「风险登记」（时间抖动 / serve_n 排队 / RST
  不可断言）。
