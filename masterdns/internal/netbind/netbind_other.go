//go:build !darwin && !ios

package netbind

import "net"

// On non-Darwin builds interface binding is a no-op; outbound UDP follows
// the OS default route. The iOS routing-loop problem this package solves
// does not exist outside iOS.
func dialUDPBound(network string, raddr *net.UDPAddr, _ string, local net.IP) (*net.UDPConn, error) {
	if local != nil {
		d := net.Dialer{LocalAddr: &net.UDPAddr{IP: local}}
		conn, err := d.Dial(network, raddr.String())
		if err != nil {
			return nil, err
		}
		return conn.(*net.UDPConn), nil
	}
	return net.DialUDP(network, nil, raddr)
}

func listenUDPBound(network string, _ string, local net.IP) (*net.UDPConn, error) {
	if local == nil {
		local = unspecifiedIPForNetwork(network)
	}
	return net.ListenUDP(network, &net.UDPAddr{IP: local, Port: 0})
}
