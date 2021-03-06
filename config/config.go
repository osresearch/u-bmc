// Copyright 2018 the u-root Authors. All rights reserved
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:generate make

package config

import (
	"github.com/u-root/u-bmc/pkg/bmc/ttime"
)

type Version struct {
	Version string
	GitHash string
}

type Config struct {
	RoughtimeServers    []ttime.RoughtimeServer
	NtpServers          []ttime.NtpServer
	StartDebugSshServer bool
	DebugSshServerKeys  []string
	Version             Version
}

var (
	DefaultConfig = &Config{
		// The philosophy behind the time configuration is to use a fast, simple, and
		// authenticated time protocol for the initial time configuration followed
		// by a refined adjustment by (unauthenticated) NTP for precision.
		// This severely limits how much an NTP server can lie to u-bmc (+/- a few
		// seconds) which makes it a mild inconvenience when reading logs but that's
		// about it.
		//
		// Other BMCs choose to trust the host's clock but given that the host
		// could be compromised and trying to fool the BMC into accepting a
		// bad time source that's not what u-bmc does.
		//
		// Instead, u-bmc will refuse to execute any remote actions until an accurate
		// time source has been established.
		RoughtimeServers: []ttime.RoughtimeServer{
			// TODO(bluecmd): Doubled entries due to https://github.com/cloudflare/roughtime/issues/10
			{Protocol: "udp4", Address: "roughtime.cloudflare.com:2002", PublicKeyType: ttime.KEY_TYPE_ED25519, PublicKey: "gD63hSj3ScS+wuOeGrubXlq35N1c5Lby/S+T7MNTjxo="},
			{Protocol: "udp6", Address: "roughtime.cloudflare.com:2002", PublicKeyType: ttime.KEY_TYPE_ED25519, PublicKey: "gD63hSj3ScS+wuOeGrubXlq35N1c5Lby/S+T7MNTjxo="},
			{Protocol: "udp4", Address: "roughtime.sandbox.google.com:2002", PublicKeyType: ttime.KEY_TYPE_ED25519, PublicKey: "etPaaIxcBMY1oUeGpwvPMCJMwlRVNxv51KK/tktoJTQ="},
			{Protocol: "udp6", Address: "roughtime.sandbox.google.com:2002", PublicKeyType: ttime.KEY_TYPE_ED25519, PublicKey: "etPaaIxcBMY1oUeGpwvPMCJMwlRVNxv51KK/tktoJTQ="},
		},
		// While u-bmc has been granted 0.u-bmc.pool.ntp.org, they do not currently
		// offer AAAA/IPv6 records. In the mean time use Google's leap smeared
		// NTP servers that do have IPv6.
		NtpServers: []ttime.NtpServer{"time1.google.com", "time2.google.com", "time3.google.com", "time4.google.com"},

		// Enable this to have the SSH server start on bootup.
		// This is useful if you're debugging startup problems in u-bmc.
		// NOTE: The SSH server starts before trusted time has been acquired,
		// do not use in production environments.
		StartDebugSshServer: true,
		// authorizedKeys is generated by the Makefile
		DebugSshServerKeys: authorizedKeys,

		Version: Version{
			Version: gitVersion,
			GitHash: gitHash,
		},
	}
)
