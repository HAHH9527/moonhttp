# 基线（T001，动工前实测 2026-10-25）

- 静态测试计数（`grep -P '^\s*(async\s+)?test\s'`，`*_test.mbt`+`*_wbtest.mbt`）== **193**
- 运行时（双 target `moon test --target native|wasm --deny-warn`）`Total tests: 191, passed: 191, failed: 0`
  - 与静态差 2＝`pool_longrun_wbtest.mbt` 两条 `#skip` 长跑（:19/:123），T015 判据以此 191 为基线
- 六门：
  - `moon check --target native --deny-warn` ✅
  - `moon check --target wasm --deny-warn` ✅
  - `moon test --target native --deny-warn` ✅ 191/191
  - `moon test --target wasm --deny-warn` ✅ 191/191
  - `moon fmt --check` ✅
  - `moon info` ✅（三包 `.mbti` 与仓库既有版本零 diff，快照即 git HEAD 版本）
- `src/client/pkg.generated.mbti`、`src/core/pkg.generated.mbti`、`src/internal/fixtures/pkg.generated.mbti`：动工前快照见 git HEAD（工作树除本特性 specs/ 目录外零改动）。
