import drivers/output/vga
import arch/x86_64/[ctrl, debug]
import arch/x86_64/interrupts/[common, faults]
import kstd/hooks


proc pfHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  chCol White, Red
  put "\n\n=== Page Fault Exception (handled by `fault_handlers::pfHandler()`) ===\n"
  let cr2 = readCr2()
  put "\n[#PF] at "
  putHex cr2
  put " rip="
  putHex frame.rip
  put "\n  --- context ---\n"
  disasAround(frame.rip, 0, 4)
  resetCol()
  1   # TODO: or 0 if the page is actually mapped

initAppend 128:
  pfHandler.registerFaultHandler(14)
