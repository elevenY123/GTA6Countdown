# Task 15 real macOS CI RED/GREEN

The first allocated Xcode 16.4 simulator build failed during Swift module
emission. The log identified actor-isolated objects instantiated in default
arguments and `WKWebView` methods whose return values did not satisfy the
void-returning navigation protocol.

The regression contract first failed against those declarations. Production
dependencies are now created inside main-actor initializers, while the WebKit
conformance exposes distinct void-returning adapter methods. The contract and
all Linux project contracts pass; the next macOS Actions run is the compiler
GREEN check.

The second compiler run passed those declarations and then exposed one final
definite-initialization error in `NewsPresentation`: a filtering closure read a
stored property before `articles` was initialized. The pinned article is now
computed in a local constant and assigned before the remaining article list is
built.

The third compiler run reached `ImageCache` and found that Swift 6 could not
infer the optional result type for the cancellation branch of its unannotated
download task. The task now declares `Task<Data?, Never>` explicitly, preserving
the existing cancellation behavior while providing the compiler's missing
context.

After compilation turned green, the full unit suite exposed two invalid
bounded-image transport assertions. The transport returned the correct
`responseTooLarge` error and stopped the protocol, but this Xcode simulator
buffers custom `URLProtocol` data before delivering it to the URLSession data
delegate. Increasing the synthetic chunk delay proved that emitted-chunk counts
cannot measure delegate cancellation timing. The tests now verify the observable
contract—typed rejection plus protocol stop—without relying on that buffering
implementation detail.

The first complete unit-test GREEN then reached UI tests. The pinned-news flow
passed, proving the app launched and navigation worked, while four assertions
queried unstable SwiftUI container identifiers. Native iOS 16 tab buttons are
exposed to XCTest by their visible Chinese labels, and an unconfigured live
news endpoint cannot provide a deterministic initial state. Root navigation
tests now query `TabBar` buttons by those user-visible labels, and the news
state test uses the same bundled fixture that already passed the detail flow.
