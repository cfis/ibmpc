# Part 4: Kermit

Having transferred `kermit.bas` from my laptop to the IBM PC I thought I was home free. I could now run `kermit` on the IBM and `C-Kermit` on my laptop (either under Windows 11 or Fedora 43) and start transferring files.

Kermit, implemented by Columbia University, would enable proper protocol-based transfers with error correction.

## Failure

The first file I wanted to transfer was `MSK315M.EXE` (MS-Kermit executable) from my laptop to the IBM. I started kermit on the PC, C-Kermit on the laptop, and started the transfer. 

What I saw on the IBM:

```
Kermit showed: %%%%%
Windows showed: Retries and errors
Result: No file created on the IBM PC
```

The `%%%%%` characters indicate failed packet retries - each `%` represents a NAK or timeout. The file was not transferred.

## What Went Wrong

Not wanting to read a bunch of basic code, I asked [ChatGPT](https://chatgpt.com/) to read `kermit.bas` and tell me what was happening. 

It came back and told me `kermit.bas` was designed to transfer text files, not binary files. 

First, on line 2070 it sends `N` in the ACK, telling the sender "I will not do 8-bit quoting".

Second, on line 3050 it opens the output file in text mode:

```basic
3050 OPEN MID$(PKTDAT$,1,L) FOR OUTPUT AS #2
```

Third, on line 4040 it uses `PRINT #` which is text-oriented output:

```basic
4040 PRINT #2, MID$(PKTDAT$,1,P);
```

Forth, on lines 7250-7270, it handles control-character unquoting but doesn't support 8th-bit quoting for high-bit characters. 

Thus `kermit.bas` was not going to work to transfer a binary program.

---

**Next:** [Part 5: Bootstrap Binary Receiver](part5-binary-receiver.md)