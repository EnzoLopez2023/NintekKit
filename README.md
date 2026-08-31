# NintekKit

Dependency-free Swift 6 shared infrastructure for Enzo's native apps. The
package provides shared models, API clients, App Intents, widget and App Group
data sharing, and ported algorithms. It does not export design tokens.

## Active consumers

NintekKit is actively consumed by exactly three apps:

- [CairnNative](https://github.com/EnzoLopez2023/CairnNative)
- [ShopKeepNative](https://github.com/EnzoLopez2023/ShopKeepNative)
- [Tare-for-iOS](https://github.com/EnzoLopez2023/Tare-for-iOS)

A breaking change must be checked against all three active consumers.

## Historical Workshop compatibility

[Workshop-for-iOS](https://github.com/EnzoLopez2023/Workshop-for-iOS) is retired,
archived/read-only, TestFlight-only, and was never publicly released. Its final
retirement state is
[`bcf46a91`](https://github.com/EnzoLopez2023/Workshop-for-iOS/commit/bcf46a91cdbc95b2b1c0e4a5c585c76369051828);
the final functional source is
[`5be54652`](https://github.com/EnzoLopez2023/Workshop-for-iOS/commit/5be546524e79b9c63b2a4effb5ec24e03fe6d777),
version 2.3.0 (15).

[Workshop web](https://github.com/EnzoLopez2023/workshop) is canonical and no
longer imposes an active native parity or propagation requirement on NintekKit.
The package intentionally retains every existing `WorkshopAPI` public method,
Workshop model, Bambu model, and the behavior, source, and tests for
`CutPlan.swift` as frozen compatibility/history. Do not delete, rename,
deprecate, or change these APIs or sources, their behavior, or their tests:
archived source/history and retained TestFlight installations may still depend
on them.
