// Copyright 2019 the u-root Authors. All rights reserved
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package platform

import (
    "log"
	"github.com/u-root/u-bmc/pkg/aspeed"
	"github.com/u-root/u-bmc/pkg/bmc"
	"github.com/u-root/u-bmc/platform/supermicro-x11ssh-f/pkg/gpio"

	pb "github.com/u-root/u-bmc/proto"
)

type platform struct {
	a *aspeed.Ast
	g *bmc.GpioSystem
	gpio.Gpio
}

func (p *platform) InitializeGpio(g *bmc.GpioSystem) error {
	g.Hog(map[string]bool{
		"PWR_LED_N":      false,
	})

	go g.ManageButton("PWR_BTN_N", pb.Button_BUTTON_POWER, bmc.GPIO_INVERTED)
	go g.ManageButton("RST_BTN_N", pb.Button_BUTTON_RESET, bmc.GPIO_INVERTED)
	return nil
}

func (p *platform) InitializeSystem() error {
	// Configure UART routing:
	// - Route UART2 to UART3
	// TODO(bluecmd): Platform dependent
	p.a.Mem().MustWrite32(0x1E789000+0x9c, 0x6<<22|0x4<<19)


	// Unlock the SCU registers with the password
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x0, aspeed.SCU_PASSWORD)

	// Re-enable the clock of UART2 to enable the internal routing
	// which will make u-bmc end of the pipe be /dev/ttyS2
	// This can be done by defining the uart2 as active in the dts, but
	// if we do that then /dev/ttyS1 might be confusing as it will not work
	// properly.
	csr := p.a.Mem().MustRead32(aspeed.SCU_BASE + 0x0c)
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x0c, csr & ^uint32(1<<16))

	// Enable UART1 and UART2 pins
	mfr := p.a.Mem().MustRead32(aspeed.SCU_BASE + 0x84)
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x84, mfr|0xffff0000)

	// Disable all pass-through GPIO ports. This enables u-bmc to control
	// the power buttons, which are routed as pass-through before boot has
	// completed.
	hws := p.a.Mem().MustRead32(aspeed.SCU_BASE + 0x70)
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x70, hws & ^uint32(3<<21))
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x8c, 0)

	// remove password, re-locking the SCU registers
	p.a.Mem().MustWrite32(aspeed.SCU_BASE+0x0, 0x0)

	log.Printf("Setting up Network Controller Sideband Interface (NC-SI) for eth0")
	go bmc.StartNcsi("eth0")
	return nil
}

func (p *platform) PwmMap() map[int]string {
	return map[int]string{
		0: "/sys/class/hwmon/hwmon0/pwm1",
	}
}

func (p *platform) FanMap() map[int]string {
	return map[int]string{
		0: "/sys/class/hwmon/hwmon0/fan1_input",
	}
}

func (p *platform) ThermometerMap() map[int]string {
	return map[int]string{
		0: "/sys/class/hwmon/hwmon1/temp1_input",
	}
}

func (p *platform) HostUart() (string, int) {
	return "/dev/ttyS5", 115200
}

func (p *platform) Close() {
	p.a.Close()
}

func Platform() *platform {
	a := aspeed.Open()
	p := platform{a, nil, gpio.Gpio{}}
	return &p
}
