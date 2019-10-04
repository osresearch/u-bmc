# Flash layout

# Serial ports

The BMC has five 16550 compatible serial ports mapped into memory and partially
shared with the x86.  There is a mux that allows either the ARM or the x86 to
send bytes to the two physical serial ports (one DB9 on the backplane, one

The default mapping is:

* uart1, 0x1e783000. DB9 serial port
* uart2, 0x1e78d000, COM2 header on mainboard
* uart3, 0x1e78e000, LPC to x86 /dev/ttySomething
* uart4, 0x1e78f000, LPC to x86 /dev/ttySomething
* uart5, 0x1e784000, BMC /dev/ttyS4 debug port, hidden on the mainboard.

The LPC mux at 0x1e789000 can reroute the uarts to other locations.
One option in the startup code copies uart5 to uart1, allowing easier access to the BMC console.

The Supermicro COM2 is a [non-standard 10-pin header on the mainboard](https://strugglers.net/~andy/blog/2015/06/19/fun-with-supermicro-motherboard-serial-headers/))
with near RS232 levels (+/- 6V).  2 = BMC RX, 3 = BMC TX, 5 = GND.  To connect this to
a null modem adapter, wire it 2<->3, 3<->2, and 5<->5.

```
+-----------+
| 6 7 8 9   |
| 1 2 3 4 5 |
+----   ----+
```




# Network ports

