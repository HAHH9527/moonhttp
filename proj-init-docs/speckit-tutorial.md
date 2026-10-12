# Spec-Kit 开发流程教程（mkhttp 项目）

本项目已安装 [GitHub Spec-Kit](https://github.com/github/spec-kit) v1.0.8（配置见 `.specify/`，脚本语言为 Python，AI 集成见 `.specify/init-options.json`）。它实现的是一套 **SDD（Spec-Driven Development，规格驱动开发）** 工作流：先把"要做什么"写成可审的规格，再据此设计、拆任务、实现。

## 十步流程速查

| # | 命令 | 阶段 | 产出 | 必要性 |
|---|------|------|------|--------|
| 0 | `/speckit-constitution` | 初始化 | `.specify/memory/constitution.md` | 一次性 |
| 1 | `/speckit-specify` | 需求 | `specs/NNN-功能名/spec.md` | 每个功能 |
| 2 | `/speckit-clarify` | 需求 | 回写进 spec.md 的澄清问答 | 推荐 |
| 3 | `/speckit-checklist` | 需求 | 定制质量检查清单 | 可选 |
| 4 | `/speckit-plan` | 设计 | `plan.md` + 设计产物 | 每个功能 |
| 5 | `/speckit-tasks` | 拆分 | `tasks.md` | 每个功能 |
| 6 | `/speckit-analyze` | 校验 | 跨文档一致性报告 | 可选 |
| 7 | `/speckit-taskstoissues` | 协作 | GitHub Issues | 可选 |
| 8 | `/speckit-implement` | 实现 | 代码 + 测试 | 每个功能 |
| 9 | `/speckit-converge` | 收尾 | 补差任务追加进 tasks.md | 推荐 |

**日常最小闭环：`specify → clarify → plan → tasks → implement`，其余按需插入。**

项目还内置了一个编排工作流 `speckit`（见 `.specify/workflows/speckit/workflow.yml`），一条命令跑完 **specify → plan → tasks → implement**，并在 spec 和 plan 之后各设一道人工审查门（gate），拒绝即中止。

---

## 目录与产物布局

```
mkhttp/
├── .specify/
│   ├── init-options.json          # spec-kit 版本、AI 集成、脚本类型
│   ├── memory/constitution.md     # 项目宪法（全局原则）
│   ├── templates/                 # spec/plan/tasks/checklist/constitution 模板
│   ├── scripts/python/            # create_new_feature.py、setup_plan.py 等辅助脚本
│   └── workflows/speckit/         # 内置全流程编排 workflow.yml
└── specs/
    └── 001-功能名/
        ├── spec.md                # 步骤 1 产出
        ├── plan.md                # 步骤 4 产出
        ├── tasks.md               # 步骤 5 产出
        ├── research.md / data-model.md / contracts/ …（步骤 4 视需要产出）
        └── checklists/            # 步骤 3 产出
```

功能目录由 `create_new_feature.py` 自动编号（`feature_numbering: sequential`），序号取 `specs/` 下现有最大值 +1。

---

## 阶段 0：一次性初始化

### `/speckit-constitution` — 制定项目宪法

产出并维护 `.specify/memory/constitution.md`，声明项目不可妥协的核心原则，例如：

- 测试先行（TDD，NON-NEGOTIABLE）
- 每个模块保持简洁、YAGNI
- 可观测性 / 版本策略 / 破坏性变更规则

**当前状态：该文件仍是模板占位符（`[PRINCIPLE_1_NAME]` 等），建议在第一个功能开工前先填好。** 后续每次 `/speckit-plan` 和 `/speckit-analyze` 都会把宪法作为硬性约束来对照检查；宪法变更也应随版本号记录。

---

## 阶段 1：需求定义

### 步骤 1：`/speckit-specify` — 生成功能规格

输入一段自然语言功能描述（越具体越好，一两句话也能展开），它会自动创建功能目录并生成 `spec.md`，内容包括：

- 功能概述与背景（**做什么、为什么**，不碰技术实现）
- 用户故事与验收场景
- 边界条件、异常路径
- `[NEEDS CLARIFICATION]` 标记——把模型不敢擅自决定的点显式标出，而不是瞎猜

原则：spec 面向产品经理/用户视角；"用什么库、怎么存数据"属于阶段 2，混进来会被要求移出。

### 步骤 2：`/speckit-clarify` — 定向澄清

扫描 spec.md，最多提出 **5 个高价值澄清问题**（每次一题、附选项），答案直接回写进 spec 的对应小节，覆盖范围包括：功能行为与边界、数据模型与契约、质量属性（性能/安全/可观测性）、edge case、兼容性与约束。已澄清项会消除对应的 `[NEEDS CLARIFICATION]` 标记。

这一步显著降低后面返工的概率，**强烈推荐在 plan 之前跑**。

### 步骤 3：`/speckit-checklist` — 质量检查清单（可选）

类比"对需求的单元测试"，基于当前上下文生成 `checklists/*.md`，例如"上线前安全清单""数据迁移验证清单"。适合需求复杂、有合规/迁移等专项关注点时用；日常小功能可跳过。

---

## 阶段 2：设计与拆分

### 步骤 4：`/speckit-plan` — 技术实现计划

从 spec.md（连同宪法）生成 `plan.md` 及配套设计产物：

- **技术栈选型**与依赖（本项目为 MoonBit，见 `agents.md`）
- **数据模型**（`data-model.md`）、**接口契约**（`contracts/`）
- **目录结构映射**：把设计落到具体的包/文件布局
- **宪法合规检查**：违背核心原则处需显式说明理由（complexity tracking）

可以多轮迭代：换了方案就重跑 plan，spec 不受影响。

### 步骤 5：`/speckit-tasks` — 任务拆分

把 plan 转成 `tasks.md`：按依赖排序、可独立验证的任务列表，典型形态：

- `[P]` 标记可并行的任务
- 每个任务带文件路径和验证方式（跑哪个测试）
- 组织成示踪弹式垂直切片：先打通端到端最小路径，再逐层加功能

### 步骤 6：`/speckit-analyze` — 交叉一致性审查（可选）

在 tasks 生成后、动手实现前，对 **spec ↔ plan ↔ tasks 三份文档**做只读交叉检查：需求是否有任务覆盖、任务是否超出 spec 范围、`[NEEDS CLARIFICATION]` 是否残留、与宪法是否冲突。发现问题输出报告，不修改文件——由你决定回头补哪份文档。

### 步骤 7：`/speckit-taskstoissues` — 转为 GitHub Issues（可选）

团队协作场景下，把 tasks.md 逐条开成按依赖排序的 Issues。单人开发可跳过。

---

## 阶段 3：实现与收尾

### 步骤 8：`/speckit-implement` — 按任务实现

逐任务执行 tasks.md：读 plan 和各契约/模型文档，按顺序写代码、跑测试，完成的任务在 tasks.md 中打勾。遇到设计层面矛盾会停下来建议先回改文档，而不是绕过去硬写。

**本项目实现阶段必须遵守的约定（来自 `agents.md`）：**

- 每片改动后跑 `moon info && moon fmt`；对比 `.mbti` diff 确认接口变化符合预期
- `moon test` 验证；快照受影响时 `moon test --update`
- 优先 `assert_eq` / `assert_true`；结构化调试输出用 `derive(Debug)` + `debug_inspect`
- MoonBit 代码按 block 组织，以 `///|` 分隔；废弃代码移入 `deprecated.mbt`
- Commit 用 Conventional 格式；注释、文档中文优先

### 步骤 9：`/speckit-converge` — 收敛补差

实现完成后（或中途接手了别人/别的工具的改动后），对照 spec/plan/tasks **审视当前代码库实况**：已完成的认可、遗漏或半成品的作为**新任务追加**到 tasks.md 末尾，让文档与代码重新对齐、实现可以续跑。适合在合并了外部修改、或 spec 有过中途变更后使用。

---

## 典型场景走法

| 场景 | 推荐路径 |
|------|----------|
| 小功能 / bug 修复 | `specify → plan → tasks → implement` |
| 需求还模糊 | `specify → clarify(多轮) → plan → …` |
| 重要功能，想稳妥 | 全流程十步，plan 后加 `analyze` |
| 团队协作派工 | …… → `tasks → taskstoissues → 各自 implement` |
| 中途接手外部改动 | `converge → implement 续跑` |
| 一键全流程 | 内置 `speckit` workflow（specify→plan→tasks→implement，中间两道审查门） |

## 几条使用心得

1. **闸门思维**：每份文档（spec / plan / tasks）都是先审后跑的关口，改需求改 spec 再向下重生成，不要直接手改 tasks 让它和 spec 脱节。
2. **`[NEEDS CLARIFICATION]` 是特性不是缺陷**：见到它就澄清，别让 AI 替你猜。
3. **宪法是活文档**：踩了新的坑、定了新的铁律，回到步骤 0 更新它，后续所有 plan/analyze 自动受益。
