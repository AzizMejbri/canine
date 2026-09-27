import drivers/output/vga
import arch/x86_64/[ctrl, disas, debug]
import arch/x86_64/interrupts/[common, faults]
import kstd/hooks

proc dfHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  chCol White, Red
  put "\n\n=== Double Fault Exception (#DF) ===\n"
  put "rip = "
  putHex frame.rip
  put "  bytes: "
  dumpBytes(frame.rip, 8)
  put "\n  --- context ---\n"
  disasAround(frame.rip, 0, 4)
  dumpRegs frame[]
  resetCol()
  1

initAppend 128:
  dfHandler.registerFaultHandler(8)
