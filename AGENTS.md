# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Spec Kit（规格驱动开发）

本项目使用 Spec Kit（speckit）进行规格驱动开发，工作流配置位于 `.specify/`。

- 最小闭环：`specify → clarify → plan → tasks → implement`，`analyze`/`converge`
  按需插入；改需求必须回改 spec 再向下重新生成，不得手改 tasks 使其与 spec 脱节。
- 项目宪法：[`.specify/memory/constitution.md`](.specify/memory/constitution.md)
  是最高治理文档，效力高于其他一切实践约定。所有 plan 与 analyze 必须对照宪法
  检查，code review 与 `/speckit-analyze` 必须验证宪法符合性；违背核心原则处
  必须显式说明理由并记录。
- 宪法不可妥协项摘要：只经公开 API 使用 `moonbitlang/async`，禁止 fork、复制
  或 vendor 上游源码，上游改动与 issue/PR 提交须事先人工批准；验收场景与测试
  先行；项目文档全部使用中文。完整原则以宪法原文为准。
- Spec Kit 流程参考：`proj-init-docs/speckit-tutorial.md`。

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## Repository Map

A full codemap is available at `codemap.md` in the project root.

Before working on any task, read `codemap.md` to understand:
- Project architecture and entry points
- Directory responsibilities and design patterns
- Data flow and integration points between modules

For deep work on a specific folder, also read that folder's `codemap.md`.
