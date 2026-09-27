import drivers/output/serial as com
import drivers/output/vga
import arch/x86_64/ctrl

{.push stack_trace: off, profiler: off, checks: off.}
proc rawoutput(s: string) =
  vga.putS s

proc panic*(s: string) {.exportc, cdecl, noreturn.}=
  chCol White, Magenta
  vga.putS "[KERNEL PANIC] "
  vga.println s
  halt()

proc panic*(msg: cstring) {.exportc: "canine_panic", cdecl, noreturn.} =
  chCol White, Magenta
  vga.putS "[KERNEL PANIC] "
  for c in msg:
    if c != '\0': vga.putC c
  halt()

{.pop.}
