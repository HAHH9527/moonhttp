# Specification Quality Checklist: 四类超时与 per-call 配置（M1-P08）

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-30
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
- [X] Focused on user value and business needs
- [X] Written for non-technical stakeholders
- [X] All mandatory sections completed

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
- [X] Requirements are testable and unambiguous
- [X] Success criteria are measurable
- [X] Success criteria are technology-agnostic (no implementation details)
- [X] All acceptance scenarios are defined
- [X] Edge cases are identified
- [X] Scope is clearly bounded
- [X] Dependencies and assumptions identified

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
- [X] User scenarios cover primary flows
- [X] Feature meets measurable outcomes defined in Success Criteria
- [X] No implementation details leak into specification

## Notes

- 家法注记（承 007 先例）：本仓 spec 为「语义基准 + 取证锚点」混合体，
  映射表/上游锚点/接线点引用属取证证据而非实现泄漏（007 spec 同形通
  过两轮 qodercn 复核与 OCR）；机制性裁决显式划归 plan（看门者构造、
  builder 形态、Request 派生与既有 RequestBuilder 的关系）。
- v2（2026-10-30）：qod-1 复核八阻断（B1–B8）全部采纳落笔——取消语
  义结构保证（R4 改写）、call 伞逸出形态钉定与 FR-002 两处有界例外
  （B2）、连接伞竞态清理义务（B3/R5）、写载体钉定 Stream（B4/R6）、
  嵌套归属改「先逸出即归属」（B5）、js 降级弱化形态（B6）、尾刷归
  读窗映射行（B7）、SC-002 R3 限定与种子偏差 D 表（B8）；十二建议
  （S1–S12）全部采纳。上游取消语义/with_timeout 实现/js Abort
Controller 均经实测取证（参考节证据链）。
- 全部清单项通过；无未决项。C1–C5/R3–R6 已按宪法 III 对拍自主裁决并
  记录理由（Clarifications 节），owner 可推翻后回改传导。
