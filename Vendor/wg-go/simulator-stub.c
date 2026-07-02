/* Simulator stub for the WireGuard Go bridge (`libwg-go.a`).
 *
 * NetworkExtension packet tunnel providers never run in the iOS Simulator, but the
 * PacketTunnelExtension target must still LINK there so the app scheme can build for
 * simulator destinations. This file implements the eight symbols exported by the real
 * wireguard-go bridge (see Vendor/wireguard-apple/Sources/WireGuardKitGo/wireguard.h)
 * as inert failures, and is compiled into `ios-sim/libwg-go.a` — see README.md.
 */

#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>

typedef void (*logger_fn_t)(void *context, int level, const char *msg);

void wgSetLogger(void *context, logger_fn_t logger_fn) {
    (void)context;
    (void)logger_fn;
}

int wgTurnOn(const char *settings, int32_t tun_fd) {
    (void)settings;
    (void)tun_fd;
    return -1; /* wireguard-go is not available in the simulator */
}

void wgTurnOff(int handle) {
    (void)handle;
}

int64_t wgSetConfig(int handle, const char *settings) {
    (void)handle;
    (void)settings;
    return -1;
}

char *wgGetConfig(int handle) {
    (void)handle;
    return NULL;
}

void wgBumpSockets(int handle) {
    (void)handle;
}

void wgDisableSomeRoamingForBrokenMobileSemantics(int handle) {
    (void)handle;
}

const char *wgVersion(void) {
    return "simulator-stub";
}
