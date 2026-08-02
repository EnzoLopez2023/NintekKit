# AGENTS.md — NintekKit

Dependency-free Swift 6 shared package: shared models, API clients, App Intents, widget / App Group data sharing, and ported algorithms (cut-plan optimiser, spaced-repetition scheduler).

## Start here
- **Cross-app standards:** https://github.com/EnzoLopez2023/azure-infra/blob/main/STANDARDS.md
- **Cross-repo product map:** https://github.com/EnzoLopez2023/azure-infra/blob/main/PORTFOLIO.md

> Agent sessions run in git worktrees, so relative paths into sibling repos (`../foo/BAR.md`) do **not** resolve. The cross-repo facts below are inlined deliberately. Always link other repos by absolute GitHub URL.

⚠️ **Stale doc:** `azure-infra/STANDARDS.md` §7 and the nintek marketing site both claim this package provides **"design tokens"**. **It does not** — there are no colour, typography or spacing exports. It is **API + models + widget infrastructure only.**

## Related surfaces — consumed by exactly four apps

- [CairnNative](https://github.com/EnzoLopez2023/CairnNative)
- [ShopKeepNative](https://github.com/EnzoLopez2023/ShopKeepNative)
- [Workshop-for-iOS](https://github.com/EnzoLopez2023/Workshop-for-iOS)
- [Tare-for-iOS](https://github.com/EnzoLopez2023/Tare-for-iOS)

Also relevant: [workshop](https://github.com/EnzoLopez2023/workshop) (React web) owns the JS original of the cut-plan optimiser.

## Propagation rule

- **A breaking change here hits all four consumers — check every one.** There is no other safety net.
- **`CutPlan.swift` must stay in parity with the Workshop web app's `src/lib/cutPlan.ts`** (including `parseInches` fraction parsing). The two are **unit-tested for exact-match layouts**. Change one, change the other, re-run the parity tests.
