//go:build darwin || ios

package netbind

import (
	"context"
	"errors"
	"net"
	"syscall"

	"golang.org/x/sys/unix"
)

func dialUDPBound(network string, raddr *net.UDPAddr, ifname string, local net.IP) (*net.UDPConn, error) {
	var ifaceIndex int
	if ifname != "" {
		ni, err := net.InterfaceByName(ifname)
		if err != nil {
			return nil, err
		}
		ifaceIndex = ni.Index
	}

	d := net.Dialer{
		Control: boundInterfaceControl(ifaceIndex),
	}
	if local != nil {
		d.LocalAddr = &net.UDPAddr{IP: local}
	}

	conn, err := d.DialContext(context.Background(), network, raddr.String())
	if err != nil {
		return nil, err
	}
	udp, ok := conn.(*net.UDPConn)
	if !ok {
		_ = conn.Close()
		return nil, errors.New("netbind: dialer returned non-UDP connection")
	}
	return udp, nil
}

func listenUDPBound(network string, ifname string, local net.IP) (*net.UDPConn, error) {
	var ifaceIndex int
	if ifname != "" {
		ni, err := net.InterfaceByName(ifname)
		if err != nil {
			return nil, err
		}
		ifaceIndex = ni.Index
	}

	if local == nil {
		local = unspecifiedIPForNetwork(network)
	}

	lc := net.ListenConfig{
		Control: boundInterfaceControl(ifaceIndex),
	}
	pc, err := lc.ListenPacket(context.Background(), network, (&net.UDPAddr{IP: local, Port: 0}).String())
	if err != nil {
		return nil, err
	}
	udp, ok := pc.(*net.UDPConn)
	if !ok {
		_ = pc.Close()
		return nil, errors.New("netbind: listener returned non-UDP connection")
	}
	return udp, nil
}

func boundInterfaceControl(ifaceIndex int) func(string, string, syscall.RawConn) error {
	if ifaceIndex == 0 {
		return nil
	}

	return func(network string, _ string, c syscall.RawConn) error {
		var v4Err error
		var v6Err error
		ctrlErr := c.Control(func(fd uintptr) {
			switch network {
			case "udp4":
				v4Err = unix.SetsockoptInt(int(fd), unix.IPPROTO_IP, unix.IP_BOUND_IF, ifaceIndex)
			case "udp6":
				v6Err = unix.SetsockoptInt(int(fd), unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF, ifaceIndex)
			default:
				v4Err = unix.SetsockoptInt(int(fd), unix.IPPROTO_IP, unix.IP_BOUND_IF, ifaceIndex)
				v6Err = unix.SetsockoptInt(int(fd), unix.IPPROTO_IPV6, unix.IPV6_BOUND_IF, ifaceIndex)
			}
		})
		if ctrlErr != nil {
			return ctrlErr
		}

		switch network {
		case "udp4":
			return v4Err
		case "udp6":
			return v6Err
		default:
			if v4Err != nil && v6Err != nil {
				return v4Err
			}
			return nil
		}
	}
}
