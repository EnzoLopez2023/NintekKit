# AGENTS.md — NintekKit

Dependency-free Swift 6 shared package: shared models, API clients, App Intents, widget / App Group data sharing, and ported algorithms (cut-plan optimiser, spaced-repetition scheduler).

## Start here
- **Cross-app standards:** https://github.com/EnzoLopez2023/azure-infra/blob/main/STANDARDS.md
- **Cross-repo product map:** https://github.com/EnzoLopez2023/azure-infra/blob/main/PORTFOLIO.md

> Agent sessions run in git worktrees, so relative paths into sibling repos (`../foo/BAR.md`) do **not** resolve. The cross-repo facts below are inlined deliberately. Always link other repos by absolute GitHub URL.

**Scope: no design tokens.** This package exports **no** colour, typography or spacing values. It provides the API client, shared models, App Intents, and widget / App Group infrastructure **only**.

**If any document or marketing page describes NintekKit as a design-token or theming package, the code is ground truth.**

## Active consumers — exactly three apps

- [CairnNative](https://github.com/EnzoLopez2023/CairnNative)
- [ShopKeepNative](https://github.com/EnzoLopez2023/ShopKeepNative)
- [Tare-for-iOS](https://github.com/EnzoLopez2023/Tare-for-iOS)

## Historical Workshop compatibility

[Workshop-for-iOS](https://github.com/EnzoLopez2023/Workshop-for-iOS) is retired,
archived/read-only, TestFlight-only, and was never publicly released. Its final
retirement state is
[`bcf46a91`](https://github.com/EnzoLopez2023/Workshop-for-iOS/commit/bcf46a91cdbc95b2b1c0e4a5c585c76369051828);
the final functional source is
[`5be54652`](https://github.com/EnzoLopez2023/Workshop-for-iOS/commit/5be546524e79b9c63b2a4effb5ec24e03fe6d777),
version 2.3.0 (15).

[Workshop web](https://github.com/EnzoLopez2023/workshop) is canonical and no
longer creates an active native parity or propagation obligation. NintekKit
nevertheless retains all existing `WorkshopAPI` public methods, Workshop models,
Bambu models, and `CutPlan.swift` behavior, source, and tests as frozen
compatibility/history. Do not delete, rename, deprecate, or change these APIs or
sources, their behavior, or their tests: archived source/history and retained
TestFlight installations may still depend on them.

## Propagation rule

- **A breaking change here hits all three active consumers — check every one.**
  There is no other safety net.
- Do not propagate Workshop web changes into the frozen native compatibility
  surfaces, including `CutPlan.swift`; there is no longer an active web/native
  parity requirement.
