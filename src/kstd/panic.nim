import arch/x86_64/ctrl
from drivers/output/vga import chCol, putS, White, Blue

{.push stack_trace: off, profiler: off, checks: off.}

template kpanic*(msg: static[string]) =
  const info = instantiationInfo(fullPaths = false)
  const full = "[KERNEL PANIC] " & info.filename & ":" & $info.line &
               ": " & msg & "\n"
  chCol White, Blue
  vga.puts full
  halt()

template kernelAssert*(cond: untyped, msg: static[string] = "") =
  if unlikely(not cond): kpanic(msg)

template assert*(cond: untyped) = kernelAssert(cond)
template assert*(cond: untyped, msg: static[string]) = kernelAssert(cond, msg)
template doAssert*(cond: untyped) = kernelAssert(cond)
template doAssert*(cond: untyped, msg: static[string]) = kernelAssert(cond, msg)

{.pop.}
