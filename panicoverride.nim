# import drivers/output/serial as com
from drivers/output/vga import put, chCol, White, Magenta
import arch/x86_64/ctrl

{.push stack_trace: off, profiler: off, checks: off.}
proc rawoutput(s: string) =
  put s

proc panic*(s: string) {.exportc, cdecl, noreturn.}=
  chCol White, Magenta
  put "[KERNEL PANIC] "
  put s
  halt()

proc panic*(msg: cstring) {.exportc: "canine_panic", cdecl, noreturn.} =
  chCol White, Magenta
  put "[KERNEL PANIC] "
  for c in msg:
    if c != '\0': put c
  halt()

{.pop.}
