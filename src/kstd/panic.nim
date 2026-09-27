import arch/x86_64/ctrl

{.push stack_trace: off, profiler: off, checks: off.}

template kpanic*(msg: static[string]) =
  const info = instantiationInfo(fullPaths = false)
  const full = "[KERNEL PANIC] " & info.filename & ":" & $info.line &
               ": " & msg & "\n"
  chCol White, Blue
  vga.putS full
  ctrl.halt()

template kernelAssert*(cond: untyped, msg: static[string] = "") =
  if not cond:
    const info = instantiationInfo(fullPaths = false)
    const full = "[KERNEL PANIC] " & info.filename & ":" & $info.line &
                 " `" & astToStr(cond) & "` " & msg & "\n"
    chCol White, Blue
    vga.putS full
    ctrl.halt()

template assert*(cond: untyped) = kernelAssert(cond)
template assert*(cond: untyped, msg: static[string]) = kernelAssert(cond, msg)
template doAssert*(cond: untyped) = kernelAssert(cond)
template doAssert*(cond: untyped, msg: static[string]) = kernelAssert(cond, msg)

{.pop.}
