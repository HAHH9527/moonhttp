# 履行小修（round5-opencode-fixes2）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：opencode（工单⑥，全新上下文，以磁盘产物为准）
- **授权**：owner 已批准 2026-10-27 ｜ **上游输入**：`analyze/round4-qoder-verify-fixes.md` C 节残留清单（C-1 WARNING + C-2/C-4/C-5 INFO；C-3 为过程取证项，归原会话另行回报，本轮不处置）
- **写入范围声明**：本轮唯一写入 = `tasks.md`（C-1/C-4）、`data-model.md`（C-2）、`analyze/round3-opencode-fixes.md`（仅 C-5 两处转引行号 + 尾部「round5 订正登记」一行）、本文件。零 git 写操作；未触碰 `src/`、`docs/`、`proj-init-docs/`、`.opencode/`、`.specify/`、3 个 `pkg.generated.mbti`；未运行任何 `moon` 命令。spec.md / contracts/ / plan.md / research.md / quickstart.md / checklists/ 零触碰。

---

## 一、逐条履行（C-1 / C-2 / C-4 / C-5）

### C-1（WARNING）T012 实现条款旧口径 —— **已修**

- **锚点核实**：属实。改前 tasks.md:240-241（T012 实现侧）确为「失败 `poison_release` 后透传——R6」，与 T004:105-107（「轮内唯一毒化归属点；drain/超限路径不另写 catch」）、data-model.md:43-44（「`drain_intermediate` 内不写 catch/毒化，错误纯透传」）、R6（research.md:181-184）三处互斥。
- **改前原文**（tasks.md:240-241）：

  >   （`lease.conn.skip_response_body()` 直调，失败 `poison_release`
  >   后透传——R6）替换 T005 的最小 advance；`ensure_lease` keep 分支

- **改后原文**（tasks.md:241-243）：

  >   （`lease.conn.skip_response_body()` 直调，失败纯透传——drain 内
  >   不写 catch/毒化，毒化由轮级 `errdefer poison_release()` 单点归属，
  >   data-model 实体 1 注记，round3 D-2；R6）替换 T005 的最小 advance；
  >   `ensure_lease` keep 分支

- **位置**：`tasks.md:241-243`（改前 :240-241；因本条扩 1 行，以下内容整体 +1 行）。
- **红绿对保持不动**：红侧 P06-US6 补②（现 :235-240，「`skip_response_body` 失败 → `poison_release` → 错误透传……连接不回池」）逐字未改——该段描述用例的可观测断言面（毒化行为发生、连接不回池），与「毒化由轮级 errdefer 单点实现」的机制归属口径兼容（同 round4 8b 对 R6 :189-190 的兼容性判法）；任务名「排干失败毒化」（:230）同样未动。

### C-2（INFO）data-model 伪码注释未随归属注记同步 —— **已修**

- **锚点核实**：属实。改前 data-model.md:21 行内注释为「// R6：conn 上 skip（毒化透传）」，与同文件 :41-48 归属注记（drain 内不写 catch/毒化、纯透传）可读出两义。
- **改前原文**（data-model.md:21）：

  >       drain_intermediate(response)                     // R6：conn 上 skip（毒化透传）

- **改后原文**（data-model.md:21）：

  >       drain_intermediate(response)                     // R6：conn 上 skip（失败纯透传，毒化由轮级 errdefer 归属——D-2 注记）

- **位置**：`data-model.md:21`（1:1 行内替换，全文件行号零漂移，归属注记仍居 :41-48）。

### C-4（INFO）T005 编号规约表述与 T007③ 两读并存 —— **已修**

- **锚点核实**：属实。改前 tasks.md:123-124「编号对齐 spec US-1 验收场景 1/2/4/5」与 T007:150「P06-US1③（红；spec 场景 3……）」并存，「与 spec 同号」是否统一规则二义。
- **改前原文**（tasks.md:123-124）：

  >   `src/client/call_test.mbt` 写 P06-US1①②④⑤（编号对齐 spec US-1
  >   验收场景 1/2/4/5；④⑤为 C2/300 修正固化黑盒——round3 D-1 补）

- **改后原文**（tasks.md:123-125）：

  >   `src/client/call_test.mbt` 写 P06-US1①②④⑤（编号=spec US-1 验收
  >   场景号：①②③④⑤ 中 ①②④⑤ 落本任务，③ 见 T007；④⑤为 C2/300
  >   修正固化黑盒——round3 D-1 补）

- **位置**：`tasks.md:123-125`（改前 :123-124；规则改写为单一口径：编号=spec 场景号，①②④⑤ 落 T005、③ 见 T007，与 T007 现文 :150-152 无二义衔接。本条扩 1 行）。

### C-5（INFO）round3 日志转引行号漂移 —— **已修（含一处子锚点出入，如实登记）**

- **锚点核实**：
  - 属实①：日志:50 引「spec.md:288（SC-001）」为改前锚点，实测 SC-001 现居 **spec.md:292**（U1 注记插 4 行后下移；引文「US-1–US-6 全部验收场景测试全绿」与 :292 现文逐字吻合）→ 已刷新。
  - 属实②：日志:61 引 data-model「注记（:41-50）」，实测注记实文 **:41-48**（:49 空行、:50 实体 2 标题）→ 已刷新。
  - **出入③：round4 所称「:279-282（非目标段）→ 改后实位 :283-286」在 round3 日志全文不存在**（`279-282`/`279` 全文零命中；日志内 `spec.md:` 行号引用仅 :50 一处与 :74 一处，后者 round4 已判精确且不在 C-5 范围）。且 spec.md:283-286 现文为术语表尾（prior 链/TooManyFollowUps 词条），并非非目标段——spec 非目标段实居 :204。该子项无从刷新，只登记不改，留下一轮独立校验方复核。
- **改前原文①**（round3 日志:50 局部）：

  > ……而 SC-001 第一分句（spec.md:288「US-1–US-6 **全部验收场景**测试全绿」）与 DoD-1 恰为场景口径；……

- **改后原文①**（round3 日志:50 局部）：

  > ……而 SC-001 第一分句（spec.md:292「US-1–US-6 **全部验收场景**测试全绿」）与 DoD-1 恰为场景口径；……

- **改前原文②**（round3 日志:61 局部）：

  >   - data-model.md 实体 1 伪码后新增「**处置归属（round3 D-2 裁决钉死）**」注记（:41-50）：轮级 errdefer 为轮内唯一毒化归属点……

- **改后原文②**（round3 日志:61 局部）：

  >   - data-model.md 实体 1 伪码后新增「**处置归属（round3 D-2 裁决钉死）**」注记（:41-48）：轮级 errdefer 为轮内唯一毒化归属点……

- **尾部订正登记**（round3 日志新增 :104，其余原文一字未动）：

  > *round5 订正登记（工单⑥ @ 2026-10-27）：仅按 round4 C-5 刷新本日志两处转引行号——:50「spec.md:288」→「spec.md:292」（U1 插行后 SC-001 实位）、:61「:41-50」→「:41-48」（data-model 归属注记实测区间）；其余原文一字未动。C-5 所述「:279-282（非目标段）」在本日志全文不存在，无从刷新（核详见 round5-opencode-fixes2.md）。*

- **位置**：`analyze/round3-opencode-fixes.md:50`、`:61`、新增尾部 `:104`（文件 102 行 → 104 行）。

---

## 二、交叉一致性自查

**五处互引口径表（改后实测）**——全部为同一口径「drain 不写 catch/毒化、错误纯透传；轮级 `errdefer poison_release()` 单点归属」：

| # | 处 | 现位 | 口径摘录 | 一致 |
|---|---|---|---|---|
| 1 | T004 括注 | tasks.md:105-107（未动） | 「轮内失败毒化——轮内唯一毒化归属点；drain/超限路径不另写 catch，data-model 实体 1 注记，round3 D-2」 | ✅ |
| 2 | T012 实现条款 | tasks.md:241-243（本轮改） | 「失败纯透传——drain 内不写 catch/毒化，毒化由轮级 `errdefer poison_release()` 单点归属，data-model 实体 1 注记，round3 D-2；R6」 | ✅ |
| 3 | data-model 归属注记 | data-model.md:41-48（未动） | 「轮级 errdefer…唯一毒化归属点…`drain_intermediate` 内不写 catch/毒化，错误纯透传」 | ✅ |
| 4 | data-model 伪码注释 | data-model.md:21（本轮改） | 「失败纯透传，毒化由轮级 errdefer 归属——D-2 注记」 | ✅ |
| 5 | R6 | research.md:181-184、:196-199（未动） | 「毒化由轮级 `errdefer poison_release()` 统一实现、drain 内不另写 catch——处置归属单点」「先 release 后 raise，errdefer 随后 no-op」 | ✅ |

- **残留扫描**：`毒化透传` / 「失败 `poison_release` 后透传」在活产物（spec/tasks/data-model/research/plan/contracts/quickstart/checklists）中**零残留**；仅存于 analyze/ 冻结报告（round1:17、round2:80、round4 自身取证引用），按 round3 日志:92「归档记录保持原样」与本轮授权不动。
- **红绿对完整性**：T012 红侧（:235-240）与任务名（:230）逐字未动；T005 红侧（:126-133）逐字未动（C-4 仅改括注）。测试承载面零变化。
- **spec/contracts/plan 不受影响（如实核）**：本轮对三者零触碰；且三者全文不含处置归属/poison 措辞（D-2 为实现级口径，round3 日志:98 已按 @oracle 裁决定性「spec/contracts 零改动」），本次小修不产生向下同步义务。research.md/quickstart/checklists 同样零涉。**无外溢。**
- **R10 映射闭合**：research.md:274（US-1-4/5 行「T005 落地」）、:285（FR-002 行「T012 补②」）未动且命名仍一致（T005/T012 任务名未改）。

## 三、行号漂移登记（观察项，未改任何归档件）

tasks.md 因 C-4（+1 行）与 C-1（净 +1 行）合计膨胀 2 行。改后实位：T004 :97-109（括注 :105-107 未变）、T005 :122-140（括注 :123-125）、T006 :141-149、T007 :150-155（③ 括注 :151-152）、T012 :230-245（红侧补② :235-240、实现条款 :241-243、keep 分支 :244-245）、T013 :246 起、T014 :264 起、T016 :288 起。**受此漂移影响的既有转引（均不改、仅登记，供下一轮独立校验按新位对账）**：round3 日志:44 的「tasks.md:242（T012 keep 分支）」现居 :245；日志:52 的「T005（:123-133）」括注现居 :123-125；round4 所引 T007:150 → 现 :150-152、T013:243-249 → 现 :246-252、T014:264-269 白盒断言 → 现 :266-271 区段、T016:285-290 → 现 :288-293 区段。data-model.md 行号零漂移（:21 注释 1:1 替换）。

## 四、遗留与移交

1. **C-3**（contracts mtime=12:33:39 的写入归因）：过程取证项，按工单归原会话回报，本轮未处置、未改判。
2. **round4 C-5 子锚点出入**：「:279-282（非目标段）」在 round3 日志不存在、spec.md:283-286 亦非非目标段（实居 :204）——不属裁决级冲突（无内容错误，纯 round4 转述瑕疵），已如实登记，留下一轮校验方对账。
3. round2 Q-B3～Q-B8 六项 INFO 维持 open（工单④口径：未获授权不动）。

**结论**：round4 C 节四条处置完毕（C-1/C-2/C-4/C-5 全部履行，红绿对与归档原文按授权边界保持），五处互引口径一致，spec/contracts/plan 零外溢。具备进入新一轮独立校验的条件。

*报告结束。生成：opencode 工单⑥ @ 2026-10-27 ｜ 本轮写入：tasks.md、data-model.md、round3 日志（C-5 两处+尾注）、本文件。*
