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
