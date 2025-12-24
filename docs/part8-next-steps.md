# Part 8: Next Steps

As discussed in [part 7](part7-debugging.md), the laptop can send data to the IBM but the IBM cannot send data to the laptop. The UART internal loopback test passed, but the external test failed. This indicates the UART chip works, but the signal isn't reaching the DB-25 pins. 

Knowing nothing about serial cards, I asked Gemini, ChatGPT and Claude what could cause this. According to them, there are two likely culprits:

1. A broken MC1488 line driver chip
2. A failed -12V power supply rail

In the RS-232 standard, a "1" is -12V and a "0" is +12V. However, the 8250 UART operates at TTL levels (0V to 5V). The MC1488 is a helper chip that boosts the 5V signal up to ±12V for the cable. Perhaps it is not working.

Gemini also said this could be a power supply issue. The MC1488 chip requires a -12V power rail to generate the negative voltage required for RS-232. It is possible the -12V rail in the IBM has failed.

So the next steps are get a multimeter and check Pin B7 on any ISA slot (or the -12V pin on the PSU connector) to ensure you actually have -12V. If that is working, then I likely need to buy a new card.

## How to Check the -12V Rail

Once I buy a multimeter, I will need to pull out the serial card to have access to the ISA slot. Then with the IBM turned on, probe one of these locations:

| Location      | Pin                   | Expected       |
|---------------|-----------------------|----------------|
| ISA slot      | B7 (-12V) vs B1 (GND) | -10V to -12.6V |
| PSU connector | -12V wire vs GND      | -10V to -12.6V |

If the -12V rail measures correctly, then the MC1488 chip on the serial card is likely broken and I should try another card. Note it possible the ISA slot has an issue, but I don't have any other unused slots.

If the -12V rails fails, then I'll be watching some YouTube videos to figure out how to fix it.