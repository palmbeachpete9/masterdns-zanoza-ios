// Package netbind centralises outbound UDP dialing so every socket can be
// bound to a specific physical network interface AND its primary IP
// address. The combination defeats third-party iOS NetworkExtensions
// (Happ, Shadowrocket, etc.) that would otherwise capture our DNS-tunnel
// traffic: setsockopt(IP_BOUND_IF) tells the kernel which interface to
// emit on; binding to the interface's own source IP forces source-address
// selection so the foreign NE cannot rewrite the route based on a default
// route it owns.
package netbind

import (
	"net"
	"sync"
	"sync/atomic"
)

var (
	iface       atomic.Pointer[string]
	addrV4      atomic.Pointer[string]
	addrV6      atomic.Pointer[string]
	hooksMu     sync.Mutex
	hooks       = map[uint64]func(){}
	hookCounter uint64
)

// SetInterface records the BSD interface name (e.g. "en0", "pdp_ip0") that
// every subsequent DialUDP should bind its socket to. Pass "" to disable
// binding and fall back to the OS default route.
//
// If the effective name changes, all registered OnChange hooks fire so
// callers can drop cached sockets that are bound to the previous interface.
func SetInterface(name string) {
	prev := iface.Load()
	previous := ""
	if prev != nil {
		previous = *prev
	}
	if previous == name {
		return
	}
	copy := name
	iface.Store(&copy)
	fireHooks()
}

// SetAddress records the primary IPv4 and IPv6 addresses of the active
// physical interface. Either may be empty. Changes fire OnChange hooks so
// callers drop sockets bound to the previous local IP.
func SetAddress(ipv4, ipv6 string) {
	changed := false

	prevV4 := ""
	if p := addrV4.Load(); p != nil {
		prevV4 = *p
	}
	if prevV4 != ipv4 {
		v := ipv4
		addrV4.Store(&v)
		changed = true
	}

	prevV6 := ""
	if p := addrV6.Load(); p != nil {
		prevV6 = *p
	}
	if prevV6 != ipv6 {
		v := ipv6
		addrV6.Store(&v)
		changed = true
	}

	if changed {
		fireHooks()
	}
}

// Current returns the currently configured BSD interface name, or "" if
// no binding is configured.
func Current() string {
	p := iface.Load()
	if p == nil {
		return ""
	}
	return *p
}

// CurrentIPv4 returns the currently configured primary IPv4 address.
func CurrentIPv4() string {
	p := addrV4.Load()
	if p == nil {
		return ""
	}
	return *p
}

// CurrentIPv6 returns the currently configured primary IPv6 address.
func CurrentIPv6() string {
	p := addrV6.Load()
	if p == nil {
		return ""
	}
	return *p
}

// HookHandle identifies a callback previously installed via OnChange. Pass
// it to RemoveHook to unregister so the caller (typically a client.Client
// shutdown path) can avoid leaking references to stopped instances.
type HookHandle uint64

// OnChange registers a callback invoked whenever SetInterface or SetAddress
// receives a different value. Used by the MasterDnsVPN client to drop its
// UDP socket pool when the underlying physical link switches.
func OnChange(fn func()) HookHandle {
	if fn == nil {
		return 0
	}
	hooksMu.Lock()
	hookCounter++
	id := hookCounter
	hooks[id] = fn
	hooksMu.Unlock()
	return HookHandle(id)
}

// RemoveHook unregisters a previously installed OnChange callback. Safe to
// call with a zero handle (no-op).
func RemoveHook(h HookHandle) {
	if h == 0 {
		return
	}
	hooksMu.Lock()
	delete(hooks, uint64(h))
	hooksMu.Unlock()
}

func fireHooks() {
	hooksMu.Lock()
	snapshot := make([]func(), 0, len(hooks))
	for _, fn := range hooks {
		snapshot = append(snapshot, fn)
	}
	hooksMu.Unlock()
	for _, h := range snapshot {
		h()
	}
}

// DialUDP dials raddr over UDP. When a physical interface and/or its
// primary IP are configured, both setsockopt(IP_BOUND_IF) and bind(2) to
// the local IP are applied. With nothing configured it falls back to
// net.DialUDP.
func DialUDP(network string, raddr *net.UDPAddr) (*net.UDPConn, error) {
	name := Current()
	v4 := CurrentIPv4()
	v6 := CurrentIPv6()
	if name == "" && v4 == "" && v6 == "" {
		return net.DialUDP(network, nil, raddr)
	}
	var local net.IP
	if raddr != nil && raddr.IP != nil && raddr.IP.To4() == nil {
		// IPv6 destination → use IPv6 source
		if v6 != "" {
			local = net.ParseIP(v6)
		}
	} else {
		if v4 != "" {
			local = net.ParseIP(v4)
		}
	}
	return dialUDPBound(network, raddr, name, local)
}

// ListenUDP opens an unconnected UDP socket for WriteToUDP/ReadFromUDP
// traffic. It applies the same interface/source-IP binding as DialUDP, which
// is required for the async tunnel worker sockets on iOS.
func ListenUDP(network string) (*net.UDPConn, error) {
	name := Current()
	local := localIPForListen(network, CurrentIPv4(), CurrentIPv6())
	if name == "" && local == nil {
		return net.ListenUDP(network, &net.UDPAddr{IP: unspecifiedIPForNetwork(network), Port: 0})
	}
	return listenUDPBound(network, name, local)
}

func localIPForListen(network, v4, v6 string) net.IP {
	switch network {
	case "udp6":
		if v6 != "" {
			return net.ParseIP(v6)
		}
	case "udp4":
		if v4 != "" {
			return net.ParseIP(v4)
		}
	default:
		if v4 != "" {
			return net.ParseIP(v4)
		}
		if v6 != "" {
			return net.ParseIP(v6)
		}
	}
	return nil
}

func unspecifiedIPForNetwork(network string) net.IP {
	if network == "udp6" {
		return net.IPv6zero
	}
	return net.IPv4zero
}
