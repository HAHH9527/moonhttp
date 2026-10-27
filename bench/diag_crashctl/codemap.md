# bench/diag_crashctl/

## Responsibility

栈对照控制组（T009 复核 D3b 的佐证探针）：用同量级深度的非尾自递归
`nontail_sum(1_000_000)` 验证「栈不足则进程 abort」这一行为基线，
为「src/fixtures walk_chunks 自递归被尾调用优化、深 32k 不爆栈」的
结论提供对照证据（尾递归对照 `tail_loop(1_000_000)` 已单独运行取证）。

## Design

- 单文件可执行探针（`pkgtype(kind: "executable")`），无任何 import、无网络。
- `nontail_sum` 为非尾自递归：递归结果参与 `1 + ...` 加法，调用点之后
  仍有工作，故每层必须保留栈帧；栈耗尽时进程 abort（属预期结果）。
- 每步 `println` 留痕：若 `done-nontail` 行缺失即说明发生了栈溢出 abort。

## Flow

`main` → 打印开始标记 → `nontail_sum(1_000_000)`（百万层非尾递归）
→ 正常返回则打印返回值与 `done-nontail`；栈不足则进程在该调用内
abort，其后输出不出现。

## Integration

- 依赖：无（moon.pkg 零 import），不触碰 src/client、src/core 任何 API。
- 运行：bench/ 不参与构建；复跑时将本目录临时复制回 `src/diag_crashctl/`，
  执行 `moon fmt && moon run src/diag_crashctl --target native`，跑完移回。
- 约束：无 *_test.mbt（不进 `moon test` 基线）；一次性探针。
