import drivers/output/vga
import arch/x86_64/[ctrl, disas, debug]
import arch/x86_64/interrupts/[common, faults]
import kstd/hooks

proc udHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  chCol White, Red
  put "\n\n=== Invalid Opcode Exception (#UD) ===\n"
  put "rip = "
  putHex frame.rip
  put "  bytes: "
  dumpBytes(frame.rip, 8)
  put "\n  --- context ---\n"
  disasAround(frame.rip, 0, 4)
  resetCol()
  1

initAppend 128:
  udHandler.registerFaultHandler(6)
