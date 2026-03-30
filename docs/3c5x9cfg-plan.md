# 3C5X9CFG Plan

## Goal

Make `3c5x9cfg.com` a reliable tool for the specific job this project needs:

- inspect a 3C509B-TPO in an IBM PC 5150/XT-class machine
- restore a known-good XT/5150-oriented NIC configuration
- change the small set of settings this project actually needs
- leave the card in a state that the `3C509.COM` packet driver accepts

This is **not** a plan to clone all of `3ccfg.exe`.

## Current Understanding

What works today:

- `3c5x9cfg.com` can find the card, read the EEPROM, and display the current settings.
- It can write selected fields and recompute the checksum.
- The card and packet driver can be made to work on the IBM PC 5150.

What does not work today:

- The current custom tool only rewrites a narrow subset of the stored configuration.
- A card "fixed" with `3c5x9cfg.com` can still be rejected by `3C509.COM`.
- `3ccfg.exe` reported `NIC configuration is unreadable` after the custom tool wrote the card.

What actually fixed the card:

```dos
3CCFG /PNPRST
3CCFG configure /int:3 /iobase:300 /xcvr:tp /pnp:disabled /optimize:dos /modem:none
```

Additional observation:

- `3ccfg.exe` later reported `Unable to locate an unused I/O base address`.
- Overriding that warning and saving anyway still produced a working configuration.
- That means conflict detection is **not** the key feature to reproduce first.

## Conclusion

The current `3c5x9cfg` is not a full replacement for `3ccfg.exe`.

However, it is also not a dead end. The likely missing piece is that `3ccfg.exe` writes additional configuration words and/or internal configuration bits beyond the subset currently handled by `3c5x9cfg`.

The right next step is to turn `3c5x9cfg` into a **constrained profile writer** for this machine, not a general-purpose 3Com configuration utility.

## Non-Goals

This effort should **not** try to do these things initially:

- replicate all menus or features of `3ccfg.exe`
- reproduce 3Com's automatic I/O conflict detection
- support every EtherLink III model or every bus mode
- optimize for systems other than the IBM PC 5150 / XT-class target in this repo

## Target Scope

The first acceptable version of `3c5x9cfg` should support:

- read-only status display
- raw EEPROM dump for comparison/debugging
- restoring a known-good 5150 profile
- setting:
  - IRQ
  - I/O base
  - transceiver
  - PnP disabled
- recomputing any required checksum(s)
- producing a card state that passes real validation:
  - `3C509.COM 0x60` loads successfully
  - `3ccfg.exe` no longer reports unreadable configuration

## Working Assumption

The problem is not that the current utility writes the wrong checksum.

The problem is that it only updates the fields it knows about:

- EEPROM word 8: transceiver + I/O base
- EEPROM word 9: IRQ
- EEPROM word 15: checksum

That is enough to make the card *look* correct in a status dump, but not enough to leave the full board configuration in a coherent state for the packet driver and `3ccfg.exe`.

## Plan

### Phase 1: Offline Analysis

Do this before touching the IBM PC again.

1. Add a raw EEPROM dump mode to `3c5x9cfg`.
2. Add a machine-readable output format that is easy to compare by hand or script.
3. Audit all currently known writable configuration words and document which ones `3c5x9cfg` touches today.
4. Review 3Com/NESTOR documentation and any available source to identify the additional fields that matter for:
   - PnP / ISA activation behavior
   - DOS optimization
   - modem / transceiver / media behavior
   - any resource or board mode fields written by `3ccfg.exe`
5. Keep the C version (`src/3c5x9cfg.c`) aligned with the assembly version as a reference implementation.

### Phase 2: Capture Reference Data From Real Hardware

When the IBM PC is available again, gather a small set of reference states.

Required captures:

1. EEPROM dump from the current **working** card state.
2. Screen output from `3c5x9cfg.com` for that same working state.
3. Screen output from `3ccfg.exe` showing the working configuration.
4. Confirmation that the packet driver still loads:

```dos
3C509 0x60
```

If practical, also capture:

1. A dump immediately after `3CCFG /PNPRST`.
2. A dump after `3ccfg.exe` writes a fresh profile but before any later network testing.
3. A dump from a deliberately broken or partially configured state.

The main purpose is to diff:

- broken state vs working state
- current custom-tool writes vs `3ccfg.exe` writes

### Phase 3: Implement a Known-Good Profile Writer

Use the captured working state as the baseline.

Implementation direction:

1. Add a mode that writes a **known-good baseline profile** for this machine.
2. After restoring the baseline profile, apply user-requested overrides for:
   - IRQ
   - I/O base
   - transceiver
   - PnP disable
3. Recompute checksum(s).
4. Re-read the EEPROM and verify the stored values match what was written.

This should be treated as:

- first: restore a coherent board profile
- second: apply a small number of safe customizations

not:

- patch three fields in isolation and hope the rest of the board state is valid

### Phase 4: Validation On Hardware

A change is not complete until it passes these checks on the IBM PC.

Required validation:

1. `3c5x9cfg.com` reports the expected values.
2. Reboot succeeds normally with the NIC installed.
3. `3C509.COM 0x60` loads without:
   - `NIC configuration is unreadable`
   - `packet driver failed to initialize the board`
4. `DHCP.EXE` obtains an address.
5. A simple mTCP command works.

### Phase 5: Tighten Scope and Documentation

Once the profile-writer path works:

1. Update the usage text and docs to describe the supported modes accurately.
2. Document that the utility targets a constrained 5150/XT use case.
3. Only then consider whether broader `3ccfg.exe` replacement goals are worth pursuing.

## Proposed CLI Direction

This does not need to be final, but a shape like this is reasonable:

```dos
3C5X9CFG                 ; show current settings
3C5X9CFG /DUMP          ; dump raw EEPROM words
3C5X9CFG /RESTORE5150   ; write known-good baseline profile
3C5X9CFG /RESTORE5150 /IRQ:3 /IO:300 /XCVR:TP /PNP:DISABLED
```

The important design point is that `RESTORE5150` is explicit. It should be clear when the tool is doing a full-profile write versus a read-only inspection.

## Success Criteria

This effort is successful when all of the following are true:

- `3c5x9cfg.com` can recover a card that `3ccfg.exe` previously had to rebuild
- the recovered card boots and initializes on the IBM PC 5150
- `3C509.COM 0x60` loads successfully
- mTCP works afterward
- the documented workflow no longer depends on `3ccfg.exe` for the normal 5150 case

## Risks

- Some required fields may be poorly documented.
- The exact bits that `3ccfg.exe` changes may vary by board state.
- A "working" profile may include fields whose meaning is not obvious from the public docs.
- Real validation is bottlenecked by access to the IBM PC hardware.

## Estimated Effort

Rough estimate:

- offline analysis and code changes: moderate
- first on-hardware proof of concept: likely one focused hardware session
- cleanup and confidence-building: another iteration after that

In other words: this looks feasible, but it should be approached as a small recovery tool project, not a quick one-line fix.

## Relevant Files

- `src/3c5x9cfg.asm`
- `src/3c5x9cfg.c`
- `docs/part10-3com-nic.md`
- `programs/3ccfg.exe`
- `programs/3c509.com`
