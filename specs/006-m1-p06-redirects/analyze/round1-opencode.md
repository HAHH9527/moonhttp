# Specification Analysis Report（round1-opencode）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：OpenCode（工单②重发，owner 已批准自主推进）
- **命令**：`/speckit.analyze`（技能版本基目录 `.agents/skills/speckit-analyze`）
- **分析对象**：`specs/006-m1-p06-redirects/` 全部产物（spec/plan/tasks/research/data-model/quickstart/contracts/checklists），对照 `.specify/memory/constitution.md`（v1.2.0）与种子 `docs/roadmap/M1/P06-redirects.md`
- **只读声明**：本命令契约本为只输出不写文件；唯一写入 = 本文件（工单②第 2 条要求，供 qoder 复核方交叉校验）。未执行任何 git 写操作；未触碰工作区 3 个 `pkg.generated.mbti` 未提交改动（`git status --porcelain` 核对：仅 `src/client`、`src/core`、`src/internal/fixtures` 三处既有 M 标记 + 未跟踪 `specs/006-m1-p06-redirects/`）；未改动 speckit command/skill 定义。
- **预检结果**：`check-prerequisites.ps1 -Json -RequireSpec -RequireTasks -IncludeTasks` → `FEATURE_DIR=specs/006-m1-p06-redirects`，AVAILABLE_DOCS 齐备；`.specify/extensions.yml` 不存在（before/after 钩子均无，静默跳过）。
- **严重级别口径**：本报告按工单要求输出 CRITICAL/WARNING/INFO 三级；与技能启发式（CRITICAL/HIGH/MEDIUM/LOW）映射为 CRITICAL=CRITICAL，WARNING=HIGH/MEDIUM，INFO=LOW/记录性。宪法 MUST 冲突一律 CRITICAL。

---

## 1. 发现总表

| ID | 类别 | 级别 | 位置（文件:行号） | 摘要 | 建议 |
|----|------|------|-------------------|------|------|
| C1 | 覆盖缺口 | **WARNING** | spec.md:221-223（FR-002「排干失败 MUST 毒化」）；research.md:175-178（R6 skip 失败→`poison_release` 后透传，P07 将在该错误上 recover）；tasks.md:218-226（T012 仅测成功排干/干净流/事件标记）；research.md:259-278（R10 映射表无 FR-002 行） | FR-002 的**失败半边**（`skip_response_body` 失败 → 毒化 → 连接不回池 → 错误透传）无任何红绿对承载：T012 只覆盖成功排干，R10 映射表整行缺席，SC-001「FR/US 全部验收场景全绿」对无测试的路径不可判定。夹具能力已在场（`mount_truncated`/`RouteScript::Truncated`，fixtures mbti:87、66），补测零扩展成本 | 在 T012（或独立 WB 任务）补「中间体排干失败 → poison → 连接不回池 → 错误透传」用例（先红后绿），并在 research R10 表补 FR-002 行；修复由后续环步骤执行，本报告不改动 |
| U1 | 边界不可达 | INFO | spec.md:167-168（Edge Cases「HEAD/GET 带 body 的异常形态」）；data-model.md:60-62（真值表 GET/HEAD 行「体原样」）；core request.mbt:116-126（`Get/Head 带 body → MethodBodyMismatch` 构造期拒绝）；core mbti:110-116（`Request` 为 `pub struct`，外部不可字面构造） | spec 边界用例描述的「HEAD/GET 带 body」在 M1 构造面**不可达**（RequestBuilder::build 拒体组 + Request 非字面可构造）；真值表「体原样」对该行恒为无体，语义无歧义，但条款未标注不可达，implement 期可能误建不可构造的夹具用例 | 在 spec 边界用例补一句「M1 构造面不可达（MethodBodyMismatch 门），条款为防御性描述」，或移至非目标注记 |
| I1 | 账目不一致 | INFO | plan.md:57（Scale/Scope「测试 2 文件」）；plan.md:105（`call_test.mbt # 新`）；tasks.md:39（「新测试 `call_test.mbt` 增补」）；磁盘实况：`src/client/call_test.mbt` 已存在（P05 产物） | plan 将 `call_test.mbt` 记为「新」文件，与磁盘现状（已存在、应增补）及 tasks 口径（增补）不符；实际文件账目为**增 2**（follow_up.mbt、follow_up_wbtest.mbt）**改 4**（http_client/exchange/body_bridge/call_test），非 plan 的「增 1 改 3 测试 2」 | plan 归档时订正 Scale/Scope 与 Project Structure 两处账目（不改语义、不影响执行序） |
| I2 | 映射漂移 | INFO | research.md:277（R10 表 FR-009 行元测试记为「P06-WB 黑盒」）；tasks.md:227-233（FR-009 实落为黑盒 `call_test.mbt` 的 P06-US6 补①，T013）；tasks.md:222-223（白盒 P06-WB⑤ 是 T012 的事件标记断言，非 FR-009 本体） | R10 映射表 FR-009 行的元测试标注自相矛盾（WB=白盒 又标「黑盒」），且与 tasks 实际落位（T013 黑盒）不一致，易误导 implement 按白盒落点写测试 | R10 表 FR-009 行订正为「P06-US6 黑盒（T013）」 |
| D1 | 宪法 II 落点 | INFO | spec.md:372-376（「量化归 P10 重定向场景基准」「本包测试不断言延迟数字」）；docs/roadmap/M1/P10-benchmark-gate.md（在场）；constitution.md:33（「性能相关改动必须附带基准数据」） | P06 属防退化型性能面：两项防退化均有验收断言（US-6 连接计数/干净流），量化基准显式延后 P10 并已记录——符合宪法「显式记录例外」口径，**非违宪**。提醒：P10 工作包须实际承接「重定向场景基准」，否则欠账悬空 | P10 spec 生成时回引本 spec 性能影响节，确保承接 |
| N1 | 健壮性注记 | INFO | data-model.md:22-25（实体 1 伪代码：跨 host 分支已 `release_lease`，其后超限 guard else 再 `release_lease`——双 release 路径）；body_bridge.mbt:67-76（既有 `release_lease`「已 None ⇒ no-op」幂等） | 伪代码在「跨 host ∧ 超限」组合下会出现二次 release；经核实既有处置单点已幂等，**无实际风险**，仅提示 implement 保持 INV-1「处置完成即置 None」语义不被改动 | 无需行动；若重构 `release_lease` 须保留 no-op 幂等（可加注释钉住） |

**CRITICAL：0 ｜ WARNING：1 ｜ INFO：5**

---

## 2. 覆盖矩阵

### 2.1 FR ↔ 任务/测试（spec.md:218-269 FR-001~012）

| 需求 | 有任务？ | 任务 ID | 备注 |
|------|---------|---------|------|
| FR-001 轮间取消裸 `CallCancelled` | ✅ | T004（WB③④） | research R10:273 映射在场 |
| FR-002 排干+毒化 | ⚠️ 半覆盖 | T012 | 成功排干/干净流已覆盖；**失败→毒化半边零测试（C1）** |
| FR-003 决策表五行 | ✅ | T002（WB①）、T005、T007、T008、T015、T016 | 行 4/5 Terminal 行 T002 先行，T015 黑盒收口，T016 穷举 |
| FR-004 跨 host 剥头 | ✅ | T011 | 双向字节断言 + 大小写变体 |
| FR-005 上限 20 计数语义 | ✅ | T014（WB⑥） | 计数位置（排干后/发送前）有白盒断言 |
| FR-006 prior 链 | ✅ | T006 | 链深/顺序/无体三断言（INV-5） |
| FR-007 同 host 租约保持 | ✅ | T012（keep）、T013（swap） | SC-003 计数双断言 |
| FR-008 Location 门 | ✅ | T005（主路径）、T010（穷举+回退） | 三形态 + 缺失/非法 |
| FR-009 中间 Connection: close | ✅ | T013 | 关闭不回池 + follow-up 新连接 |
| FR-010 代次折叠 | ✅ | T003（WB②） | fold_count/复用断言 |
| FR-011 js 不实现循环 | ✅ | T018 | 编译检查 + 一致性复核（非门禁） |
| FR-012 .mbti 冻结面 | ✅ | T002（增量核对）、T017（收口对账） | contracts §1 对账面 |

### 2.2 SC ↔ 证据承载（spec.md:288-306 SC-001~008）

| SC | 承载 | 备注 |
|----|------|------|
| SC-001 全场景双 target 全绿 | T017 逐条记录证据测试名 | 行为任务 T002-T015 红绿对 |
| SC-002 超限可判别 | T014 | 21 跳 + A→B→A |
| SC-003 租约语义可证 | T012 / T013 | 连接计数双断言 |
| SC-004 剥头可证 | T011 | 双向字节级 |
| SC-005 prior 链可证 | T006 | 深度+顺序+状态码三断言 |
| SC-006 排干可证 | T012 | 干净流 |
| SC-007 外部网络依赖 0 | 全任务（结构性保证） | 全部 P03 本地夹具 |
| SC-008 公开面零泄漏 | T002 / T017 | contracts §1 对账 |

**Unmapped tasks**：T001（基线快照，治理任务，tasks.md:15 已显式豁免红绿对）——合规。

---

## 3. 种子覆盖核查（docs/roadmap/M1/P06-redirects.md → spec.md）

| 种子条目（行号） | spec 承载 | 结论 |
|------|------|------|
| 功能描述（seed L9-15：循环/Location resolve/决策表/20 跳/prior 链/跨 host 剥头/skip 排干/D7 裁剪） | spec 摘要+FR-001~009 | ✅ 全覆盖 |
| 范围·包含 6 项（seed L19-38） | spec.md:190-198 | ✅ 全覆盖 |
| 范围·非目标 6 项（seed L40-45） | spec.md:200-214 | ✅ 全覆盖（408 语义按 5.5.0 对拍修正后归 P07，见下） |
| US-1~US-6（seed L47-116） | spec US-1~US-6（L22-157） | ✅ 六故事一一对应，优先级继承（US-5=P2） |
| 边界用例 6 条（seed L118-123） | spec Edge Cases 7 条（L160-177） | ✅ 超集（新增 21 跳精确语义条） |
| 需求种子 FR-001~007（seed L125-133） | spec FR-001~007（L218-253）同号继承 + FR-008~012 扩展 | ✅ |
| 关键设计要点 3 条（seed L135-142：循环骨架/头改写重折叠/L3 代次缓存） | C4 裁决（spec.md:328-334）、FR-010（L259-262） | ✅（「302 对 PUT/POST 之外方法语义在 spec 对齐」→ 已按 C2 对拍完成） |
| 澄清问题 C1~C4（seed L172-180） | spec Clarifications 7 条（L405-432）+ Assumptions（L308-341） | ✅ 全部裁决回记，无 [NEEDS CLARIFICATION] |
| 包级 DoD 1-4（seed L182-187） | spec 包级 DoD 1-4（L384-393） | ✅ |
| target 矩阵/性能影响/测试方案（seed L152-170） | spec L364-382 | ✅ |

**种子三处过时/待对拍口径的修正链**（均有源码取证与回记，符合宪法 III「差异显式记录」）：
1. C1 剥 Cookie：seed L174-175 → spec Assumptions L310-319 + 映射表 L358（有意差异，M3/11 回改）；
2. C2 降级集合「仅 POST」作废：seed L62-63 → Clarifications 第 2 条 L413-416 + US-1-4/US-1-5（L43-48）+ 映射表 L351；
3. 「300 不跟随」作废：seed L99/L105/L30 → Clarifications 第 3 条 L417-419 + FR-003 行 1（L225-227）+ US-5 收窄（L132-135）+ 映射表 L354。

**覆盖率：100%**（无种子条目丢失、无 spec 幽灵需求——spec 新增项 FR-008~012 均可在种子「关键设计要点/边界用例/澄清种子」找到出处或为 clarify 源码取证补充）。

---

## 4. 宪法对照（constitution.md v1.2.0）

| 原则 | 结论 | 证据 |
|------|------|------|
| I 非侵入底座（不可妥协） | ✅ 通过 | 仅经 `@async`/`@http` 公开 API：`skip_response_body` 在上游公开面（.mooncakes http mbti:80）；js patch 方案显式否决（plan.md:66）；零 fork/vendor；上游改动零需求 |
| II 性能优先 | ✅ 通过（1 条记录性提醒 D1） | 防退化两项带验收断言（spec.md:372-376）；非侵入改动无「基准对比报告」义务；量化归 P10 已显式记录 |
| III OkHttp 语义对齐 | ✅ 通过 | 5.5.0 源码对拍（research R1 file:line 锚点）；四处显式差异 + D7 全部登记于映射表（spec.md:349-362）；种子两处过时口径按基准修正并回记 |
| IV 验收场景与测试先行（不可妥协） | ⚠️ 一处缺口（即 C1，WARNING） | 红绿对编排合规（tasks.md:12-17，003/005 先例引用属实）；16/17 验收场景+FR 失败半边之外全覆盖；**FR-002 失败→毒化半边无测试承载** |
| V Target 策略 | ✅ 通过 | target 矩阵显式（spec.md:364-370）；native/wasm 双绿门、js 仅编译检查且标注未验证、wasm-gc 排除说明在场 |
| VI 简洁与接口纪律 | ✅ 通过 | 公开面增量=且仅=两件套（contracts §1 与 client mbti 现状逐项吻合）；core/fixtures 零 diff 契约（§2/§3）；C4 单槽缓存 YAGNI 论证在场（research.md:107-111） |
| VII 中文表达（不可妥协） | ✅ 通过 | 七份产物全中文；任务命名含中文描述 |

**Constitution Alignment Issues**：无 MUST 级违宪。唯一实质缺口为 C1（宪法 IV 测试先行在 FR-002 失败半边的覆盖缺口），属 WARNING 非违宪——该行为路径的**实现义务**已由 FR-002 明示，缺的是先红后绿承载。

---

## 5. 锚点核实附录（磁盘实证，2026-10-27）

对 plan/research/tasks 引用的代码锚点逐一核实（只读）：

| 声明锚点 | 磁盘实况 | 结论 |
|------|------|------|
| T001 基线「静态测试计数 == 240」（tasks.md:55） | 同命令实测 240 | ✅ 精确 |
| T003「P05 白盒直调点 call_wbtest.mbt 5 处 exchange_once」（tasks.md:89-90） | 实测 5 处 | ✅ 精确 |
| R3/R9：exchange.mbt folded_headers L60-72、exchange_once L78-86 | 完全吻合 | ✅ |
| R3/R9：http_client.mbt CallCancelled 两件套 L11-26、execute 骨架 L126-187 | 完全吻合（spawn 目标 L150=`exchange_once`，与 T004 换 `exchange_loop` 的前提一致） | ✅ |
| R6：exchange.mbt Connection: close token 解析 L112-124 | 实际块 L112-126（±2 行，实质命中） | ✅（微漂） |
| R6：body_bridge.mbt dispose_skip（skip 失败→poison+release）先例 L102-110、所有权注释 L10-11 | 完全吻合；`release_lease`(L68)/`poison_release`(L38) 均在场且幂等 | ✅ |
| R4/R5：core mbti `HttpUrl::resolve` L86、`HeadersVBuilder::remove` L64、RequestBuilder 五件套 L138-145、`Response::from_http` prior? 参 L158、`Response::prior` L160 | 全部精确命中 | ✅ |
| R4：「Address derive Eq」 | client mbti:22 `derive(Eq, Hash)` + `Address::new(scheme~/host~/port~)` | ✅ |
| R7：夹具「全能力在场」 | mount:84 / mount_sequence:86 / mount_truncated:87 / conn_request_counts:83 / accepted_total:81 / `Capture`:45 / `SlowReceive`:44 / `head_text`:25 / `raw_text`:26 / `BodyPlan`:10-14 | ✅ |
| R4：非 http(s) 绝对引用被 resolve 拒绝（spec.md:339-341 归 plan 核实项） | `HttpUrlError::UnsupportedScheme` 变体在场（core mbti:29） | ✅ |
| spec 引用差异编号 D7/D9/D14 | docs/roadmap/M1/README.md:83 / :85 / :90（差异清单） | ✅（注：差异表在 roadmap README，不在 proj-init-docs 原文——seed L14「README 差异 D7」指向成立） |
| contracts §1「P05 冻结面零变化」基线 | client pkg.generated.mbti 逐项吻合（placeholder:10、CallCancelled:13-14、CallStateError:16-17、execute:36 等） | ✅ |
| plan「moonbitlang/async@0.22.4 钉版」（plan.md:32） | moon.mod import 精确匹配 | ✅ |
| spec FR-001 引「P05 FR-003 先例」（spec.md:220） | specs/005-m1-p05-call-engine/spec.md CallCancelled 裸变体语义在场（L65-82） | ✅ |
| quickstart `-p hahh9527/moonhttp/client`（quickstart.md:28-30） | moon.mod name + client mbti package 声明一致 | ✅ |

**注**：3 个 `pkg.generated.mbti` 的未提交改动未影响上述任何锚点命中（行号与声明一致），工作区噪音与文档无耦合。

---

## 6. Metrics

- 总需求数：FR 12 条 + SC 8 条 + 验收场景 17 条（US-1:5、US-2:3、US-3:2、US-4:2、US-5:3、US-6:2）
- 总任务数：18（T001-T018；红绿对行为任务 14 个 T002-T015）
- 任务映射覆盖率：FR 12/12 有实现任务；**测试级覆盖 11/12 全覆盖 + FR-002 半覆盖（≈96%）**；SC 8/8 有承载
- 歧义计数：1（U1，不可达边界条款）
- 重复计数：0
- CRITICAL：0 ｜ WARNING：1（C1）｜ INFO：5（U1/I1/I2/D1/N1）

---

## 7. Next Actions（移交后续环步骤，本报告不执行修复）

1. **implement 前置（对应 C1，建议闭环后再进 T012）**：在 tasks.md T012（或新增 WB 子项）补「中间体排干失败 → `poison_release` → 连接不回池 → 错误透传」红绿对（夹具 `mount_truncated`/`RouteScript::Truncated` 已在场），并在 research.md R10 表补 FR-002 行——宪法 IV 缺口消除。
2. **低风险订正（可与 implement 并行，均为文档微调）**：
   - spec.md:167-168 标注「HEAD/GET 带 body」为 M1 构造面不可达（U1）；
   - plan.md:57/105 订正文件账目（I1）；
   - research.md:277 订正 FR-009 元测试标注为「P06-US6 黑盒（T013）」（I2）。
3. **P10 承接提醒（D1）**：P10 spec 生成时回引本 spec 性能影响节，落实「重定向场景基准」。
4. 其余一致性（决策表五行、上限精确语义、取消语义、种子修正链、宪法 I/II/III/V/VI/VII）**未发现阻断项，可进入 `$speckit-implement`**。

---

*报告结束。生成：OpenCode `/speckit.analyze` @ 2026-10-27 ｜ 唯一写入：本文件。*
