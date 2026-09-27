import arch/x86_64/interrupts/[common, faults]
import arch/arch_specific
import drivers/output/vga
import kstd/hooks
import macros
import arch/x86_64/[debug, disas]


proc dbHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  let dr6 = readDR6()
  let fromUser = (frame.cs and 3) == 3

  chCol White, Cyan
  put "\n\n=== Debug Trap (fault_handlers::dbHandler) ===\n"
  put "[#DB] rip="
  putHex frame.rip
  put " cs="
  putHex frame.cs
  put " mode="
  if fromUser:
    put "user"
  else:
    put "kernel"
  put "\n"
  if isDumpRegs(): dumpRegs(frame[])
  if isDisasMany(): disasAround(frame.rip, -4, 8)
  if isDisasRip(): disasOne(frame.rip)
  resetDebugFlags()
  put "\n"


  # --- hardware breakpoint hits (B0..B3) ---
  var hit = -1
  if dr6.b0: hit = 0
  elif dr6.b1: hit = 1
  elif dr6.b2: hit = 2
  elif dr6.b3: hit = 3

  if hit >= 0:
    let dr7 = readDR7()
    put "  breakpoint "
    putHex hit
    let bp = gBreakpoints[hit]
    if bp.used:
      put " \""
      putS bp.name
      put "\""
    put " hit @ "
    putHex slotReadAddr(hit)
    put " cond="
    put dr7.bp[hit].cond
    put " len="
    put dr7.bp[hit].len
    put "\n"
    # One-shot: disable so we don't retrap the same RIP.
    # (Matches the usual debugger pattern: hit, report, disable; the
    # caller can re-arm after stepping.)
    removeBreakpoint(hit)

  # --- single-step ---
  if dr6.bs:
    putS "  single-step trap (clearing TF)\n"

    frame.rflags = frame.rflags and not 0x100'u64

  # --- general detect: someone accessed a DR with DR7.GD=1 ---
  if dr6.bd:
    putS "  debug-register access fault (DR7.GD=1) — clearing GD\n"
    var dr7 = readDR7()
    dr7.gd = false
    writeDR7(dr7)
    writeDR6(default(DR6))
    resetCol()
    return 0   # recoverable; the offending DR access is retried

  # --- task switch ---
  if dr6.bt:
    putS "  task-switch debug exception\n"
    writeDR6(default(DR6))
    resetCol()
    return 1   # TSS task gates aren't used here; treat as fatal

  # --- RTM: bit clear ⇒ we were inside a transaction ---
  if not dr6.rtm:
    putS "  exception occurred inside an RTM region\n"
    writeDR6(default(DR6))
    resetCol()
    return 1   # we don't support TSX; a transaction shouldn't be active

  # --- no cause bits set: spurious #DB or software INT1 ---
  let anyCause = dr6.b0 or dr6.b1 or dr6.b2 or dr6.b3 or
                 dr6.bd or dr6.bs or dr6.bt
  if not anyCause:
    putS "  spurious #DB (no DR6 cause) — likely INT1 or erratum\n"
    writeDR6(default(DR6))
    resetCol()
    return 0   # must resume; SDM says ignore if no cause bits

  writeDR6(default(DR6))
  resetCol()
  0


initAppend 128:
  dbHandler.registerFaultHandler(1)
