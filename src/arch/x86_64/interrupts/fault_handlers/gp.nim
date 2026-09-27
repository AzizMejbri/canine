import drivers/output/vga
import arch/x86_64/[ctrl, disas, debug, gdt]
import arch/x86_64/interrupts/[common, faults]
import kstd/hooks

type GpInfo = object
  external: bool
  tableName: cstring
  index: uint16

proc logGdtEntry(idx: int) =
  let n = gdtEntryCount()
  if idx < 0 or idx >= n:
    put "  (index "
    putHex uint64(idx)
    put " out of GDT range, max="
    putHex uint64(n)
    put ")\n"
    return
  let base = gdtBase()
  let raw  = base[idx]
  let info = decodeEntry(raw)
  put "  GDT["
  putHex uint64(idx)
  put "]: "
  put info.typeName
  put " dpl="
  putHex uint64(info.dpl)
  put " base="
  putHex uint64(info.base)
  put " limit="
  putHex uint64(info.limit)
  put "\n"

  # 64-bit TSS is 16 bytes — also print the high base bits.
  if info.isSystem and (info.typ == 0x9 or info.typ == 0xB):
    if idx + 1 < n:
      let hi = base[idx + 1]
      put "  GDT["
      putHex uint64(idx)
      put "].hi: base[63:32]="
      putHex (hi and 0xFFFFFFFF'u64)
      put "\n"

proc decodeGpError(errc: uint64): GpInfo {.inline.} =
  result.external = (errc and 1) != 0
  let tbl = (errc shr 1) and 0x3
  result.tableName =
    case tbl
    of 0: "GDT"
    of 1: "IDT"
    of 2: "LDT"
    of 3: "IDT"    # bit pattern 0b11 also means IDT
    else: "?"
  result.index = uint16((errc shr 3) and 0x1FFF)

proc gpHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  chCol White, Red
  put "\n=== General Protection Fault (handled by `fault_handlers::gpHandler()`)===\n"
  put "[#GP]  rip  = "
  putHex frame.rip
  put "\n  cs   = "
  putHex uint64(frame.cs)
  put "\n  errc = "
  putHex frame.error
  put "\n"

  if frame.error == 0:
    put "  -> non-selector GP\n"
  else:
    let ext = (frame.error and 1) != 0
    let tbl = (frame.error shr 1) and 0x3
    let idx = int((frame.error shr 3) and 0x1FFF)

    put "  -> selector fault: "
    case tbl
    of 0: put "GDT"
    of 1, 3: put "IDT"
    of 2: put "LDT"
    else: discard
    put " index "
    putHex uint64(idx)
    if ext: put " (external)"
    put "\n"

    if tbl == 0:
      logGdtEntry(idx)

  disasAround(frame.rip, -4, 4)
  dumpRegs frame[]
  put "\n"

  resetCol()
  1

initAppend 128:
  gpHandler.registerFaultHandler(13)
