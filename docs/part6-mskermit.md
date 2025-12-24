# Part 6: Can't Send Files!

After successfully copying `mskermit` to the IBM PC I thought I was read to start transferring files!

First I started `C-Kermit` on my laptop and set it up to receive files:

```bash
set line com3           ; or /dev/ttyUSB0 on Linux
set speed 4800
set parity none
set flow none
set carrier-watch off
set modem type none
receive
```

Then on the IBM PC I started `mskermit` and typed in:

```doscon
set line com1
set speed 4800
set parity none
set flow none
set handshake none
set modem none
send LE.BAT
```

And...nothing. What went wrong?

---

**Next:** [Part 7: Debugging the Transmit Path](part7-debugging.md)
