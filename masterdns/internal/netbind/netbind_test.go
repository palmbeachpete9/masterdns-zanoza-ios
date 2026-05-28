package netbind

import (
	"net"
	"sync/atomic"
	"testing"
	"time"
)

func resetBindingsForTest(t *testing.T) {
	t.Helper()
	SetInterface("")
	SetAddress("", "")
}

func TestCurrentDefaultsToEmpty(t *testing.T) {
	resetBindingsForTest(t)
	if got := Current(); got != "" {
		t.Errorf("Current after reset = %q, want empty", got)
	}
}

func TestSetInterfaceFiresOnChangeOnDistinctValues(t *testing.T) {
	resetBindingsForTest(t)
	var count int32
	handle := OnChange(func() { atomic.AddInt32(&count, 1) })
	defer RemoveHook(handle)

	SetInterface("en0")
	SetInterface("en0") // identical → no-op
	SetInterface("pdp_ip0")
	SetInterface("")

	if got := atomic.LoadInt32(&count); got != 3 {
		t.Errorf("OnChange fired %d times, want 3", got)
	}
}

func TestRemoveHookStopsCallbacks(t *testing.T) {
	resetBindingsForTest(t)
	var count int32
	handle := OnChange(func() { atomic.AddInt32(&count, 1) })

	SetInterface("en0")
	if atomic.LoadInt32(&count) != 1 {
		t.Fatalf("hook never fired before remove")
	}
	RemoveHook(handle)

	SetInterface("pdp_ip0")
	if got := atomic.LoadInt32(&count); got != 1 {
		t.Errorf("hook fired after RemoveHook: count=%d", got)
	}
}

func TestDialUDPWithoutBindingMatchesNetDial(t *testing.T) {
	resetBindingsForTest(t)

	echo, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0})
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer echo.Close()

	go func() {
		buf := make([]byte, 64)
		_ = echo.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, addr, err := echo.ReadFromUDP(buf)
		if err != nil {
			return
		}
		_, _ = echo.WriteToUDP(buf[:n], addr)
	}()

	addr, ok := echo.LocalAddr().(*net.UDPAddr)
	if !ok {
		t.Fatalf("unexpected local addr type %T", echo.LocalAddr())
	}
	conn, err := DialUDP("udp", addr)
	if err != nil {
		t.Fatalf("DialUDP: %v", err)
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := conn.Write([]byte("ping")); err != nil {
		t.Fatalf("write: %v", err)
	}
	buf := make([]byte, 16)
	n, err := conn.Read(buf)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(buf[:n]) != "ping" {
		t.Errorf("echo mismatch: %q", buf[:n])
	}
}

func TestDialUDPWithLoopbackBindingSucceedsOnDarwin(t *testing.T) {
	resetBindingsForTest(t)

	// lo0 is always present on Darwin and on Linux test runners too.
	if _, err := net.InterfaceByName("lo0"); err != nil {
		t.Skip("lo0 not present; skipping interface-binding test")
	}
	SetInterface("lo0")
	SetAddress("127.0.0.1", "")
	defer func() {
		SetInterface("")
		SetAddress("", "")
	}()

	echo, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0})
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer echo.Close()
	addr, ok := echo.LocalAddr().(*net.UDPAddr)
	if !ok {
		t.Fatalf("unexpected local addr type %T", echo.LocalAddr())
	}

	conn, err := DialUDP("udp", addr)
	if err != nil {
		t.Fatalf("DialUDP with lo0 binding: %v", err)
	}
	defer conn.Close()
	if conn.LocalAddr().(*net.UDPAddr).IP.String() != "127.0.0.1" {
		t.Errorf("local addr = %v, want 127.0.0.1", conn.LocalAddr())
	}
}

func TestSetAddressFiresOnChange(t *testing.T) {
	resetBindingsForTest(t)
	var count int32
	handle := OnChange(func() { atomic.AddInt32(&count, 1) })
	defer RemoveHook(handle)

	SetAddress("192.168.1.42", "")
	SetAddress("192.168.1.42", "") // identical → no-op
	SetAddress("192.168.1.50", "")
	SetAddress("192.168.1.50", "fe80::1")

	if got := atomic.LoadInt32(&count); got != 3 {
		t.Errorf("OnChange fired %d times, want 3", got)
	}
	if CurrentIPv4() != "192.168.1.50" {
		t.Errorf("CurrentIPv4 = %q, want 192.168.1.50", CurrentIPv4())
	}
	if CurrentIPv6() != "fe80::1" {
		t.Errorf("CurrentIPv6 = %q, want fe80::1", CurrentIPv6())
	}
	SetAddress("", "")
}

func TestListenUDPWithoutBindingReceivesPackets(t *testing.T) {
	resetBindingsForTest(t)

	listener, err := ListenUDP("udp")
	if err != nil {
		t.Fatalf("ListenUDP: %v", err)
	}
	defer listener.Close()

	addr, ok := listener.LocalAddr().(*net.UDPAddr)
	if !ok {
		t.Fatalf("unexpected local addr type %T", listener.LocalAddr())
	}
	target := *addr
	if target.IP == nil || target.IP.IsUnspecified() {
		target.IP = net.ParseIP("127.0.0.1")
	}

	sender, err := net.DialUDP("udp", nil, &target)
	if err != nil {
		t.Fatalf("DialUDP sender: %v", err)
	}
	defer sender.Close()

	if _, err := sender.Write([]byte("ping")); err != nil {
		t.Fatalf("sender write: %v", err)
	}

	buf := make([]byte, 16)
	_ = listener.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, _, err := listener.ReadFromUDP(buf)
	if err != nil {
		t.Fatalf("listener read: %v", err)
	}
	if string(buf[:n]) != "ping" {
		t.Errorf("payload = %q, want ping", buf[:n])
	}
}

func TestListenUDPWithLoopbackBindingSucceedsOnDarwin(t *testing.T) {
	resetBindingsForTest(t)

	if _, err := net.InterfaceByName("lo0"); err != nil {
		t.Skip("lo0 not present; skipping interface-binding test")
	}
	SetInterface("lo0")
	SetAddress("127.0.0.1", "")
	defer resetBindingsForTest(t)

	conn, err := ListenUDP("udp")
	if err != nil {
		t.Fatalf("ListenUDP with lo0 binding: %v", err)
	}
	defer conn.Close()

	if conn.LocalAddr().(*net.UDPAddr).IP.String() != "127.0.0.1" {
		t.Errorf("local addr = %v, want 127.0.0.1", conn.LocalAddr())
	}
}
