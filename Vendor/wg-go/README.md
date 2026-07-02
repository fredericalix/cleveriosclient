# Prebuilt WireGuard Go bridge (`libwg-go.a`)

`ios/libwg-go.a` is the WireGuard Go bridge (`wireguard-go`) compiled as a static
library for **iOS device (arm64)**. It satisfies the `link "wg-go"` directive in
WireGuardKit's module map, so the `PacketTunnelExtension` target can link WireGuardKit
without an Xcode "External Build System" target.

Built from the official `wireguard-apple` (`master`) with Go 1.24.2:

```
git clone https://git.zx2c4.com/wireguard-apple
cd wireguard-apple/Sources/WireGuardKitGo
make PLATFORM_NAME=iphoneos ARCHS=arm64        # produces out/libwg-go.a
```

Regenerate when bumping the WireGuard or Go version.

## Simulator stub (`ios-sim/libwg-go.a`)

`ios-sim/libwg-go.a` is **not** wireguard-go: it is a stub (arm64 + x86_64 simulator)
built from `simulator-stub.c`, implementing the eight exported bridge symbols as inert
failures. NetworkExtension providers never run in the Simulator, but the extension
target must still *link* there so `xcodebuild build`/`test` against simulator
destinations keep working. The extension's `LIBRARY_SEARCH_PATHS` picks `ios/` or
`ios-sim/` per SDK (`[sdk=iphoneos*]` / `[sdk=iphonesimulator*]`).

Regenerate the stub (only needed if wireguard.h gains/loses symbols):

```
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -c -target arm64-apple-ios18.0-simulator  -isysroot "$SDK" -O2 simulator-stub.c -o /tmp/a.o
xcrun clang -c -target x86_64-apple-ios18.0-simulator -isysroot "$SDK" -O2 simulator-stub.c -o /tmp/x.o
xcrun libtool -static -o /tmp/a.a /tmp/a.o && xcrun libtool -static -o /tmp/x.a /tmp/x.o
xcrun lipo -create /tmp/a.a /tmp/x.a -output ios-sim/libwg-go.a
```
