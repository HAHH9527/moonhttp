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
moon test  --target native --deny-warn   # 门 3（默认套：不含长跑，裁决 C5）
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
# US-1 租借归还 / US-3 驱逐与 evict_all / US-4 毒化路径（P03 夹具 +
# @http.Client 原语独立驱动，不经 P05）：
moon test -p hahh9527/moonhttp/client -f "P04-US*" --target native
# US-2 场景 1（K=8 并发 100 请求串号检测）：
moon test -p hahh9527/moonhttp/client -f "P04-US2*" --target native
# Address 键隔离/规范化（FR-014）：
moon test -p hahh9527/moonhttp/client -f "P04-E*"   --target native
# 白盒：时钟注入 / conn_id 守恒 / 终结幂等（FR-018）/ 临界区不变量：
moon test -p hahh9527/moonhttp/client -f "P04-FR*"  --target native
# 夹具扩展自证（F-5/F-6/F-7 计数与次序脚本）：
moon test -p hahh9527/moonhttp/internal/fixtures -f "P04-FIX*" --target native
```

每条把 `--target native` 换成 `--target wasm` 再跑一轮（双绿门）。

## 3. 长跑/无泄漏双证据（US-2 场景 2；默认排除六门，裁决 C5）

```powershell
# skip 语法核证通过后的显式执行形态（research R8 主案）：
moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
  --include-skipped --target native
moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
  --include-skipped --target wasm
# 降级案（skip 语法核证失败）：stress 独立包 -p hahh9527/moonhttp/client/stress
```

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
