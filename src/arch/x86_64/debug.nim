import arch/arch_specific
import ./debug/[dr6, dr7, raw]
import ./disas
export dr6, dr7

proc readDR0*(): uint64 {.inline, x86_64.} = raw.rawReadDR0()
proc readDR1*(): uint64 {.inline, x86_64.} = raw.rawReadDR1()
proc readDR2*(): uint64 {.inline, x86_64.} = raw.rawReadDR2()
proc readDR3*(): uint64 {.inline, x86_64.} = raw.rawReadDR3()

proc writeDR0*(value: uint64) {.inline, x86_64.} = raw.rawWriteDR0(value)
proc writeDR1*(value: uint64) {.inline, x86_64.} = raw.rawWriteDR1(value)
proc writeDR2*(value: uint64) {.inline, x86_64.} = raw.rawWriteDR2(value)
proc writeDR3*(value: uint64) {.inline, x86_64.} = raw.rawWriteDR3(value)


type
  Breakpoint* = object
    name*   : cstring
    address*: uint64
    cond*   : BreakCond
    len*    : BreakLen
    used*   : bool

  DebugFlag* = enum
    dumpRegs  = 1
    disasRip  = 2
    disasMany = 4

proc `and`*(df1, df2: DebugFlag): uint8 {.inline.} =
  uint8(ord(df1)) or uint8(ord(df2))

proc `and`*(df: DebugFlag, dfs: uint8): uint8 {.inline.} =
  uint8(ord(df)) or dfs

converter toUint8*(df: DebugFlag): uint8 = uint8(ord df)

var gBreakpoints*: array[4, Breakpoint]
var gDebugFlags = 0'u8

const condNames: array[BreakCond, cstring] =
  ["execute", "write", "io", "rw"]

const lenNames: array[BreakLen, string] =
  ["1", "2", "8", "4"]

converter toCString*(c: BreakCond): cstring = condNames[c]
converter toCString*(l: BreakLen):  cstring = lenNames[l]

proc singleStepTrap*(debugFlags: uint8 = 0) {.noinline, x86_64.} =
  ## Set TF. The next instruction raises #DB.
  gDebugFlags = gDebugFlags or debugFlags
  asm """
    pushfq
    orq $0x100, (%%rsp)
    popfq
    ::: "memory", "cc"
  """

proc slotWriteAddr*(slot: int, address: uint64) {.inline.} =
  case slot
  of 0: writeDR0(address)
  of 1: writeDR1(address)
  of 2: writeDR2(address)
  of 3: writeDR3(address)
  else: discard

proc slotReadAddr*(slot: int): uint64 {.inline.} =
  case slot
  of 0: result = readDR0()
  of 1: result = readDR1()
  of 2: result = readDR2()
  of 3: result = readDR3()
  else: discard

proc installBreakpoint*(slot: int, name: cstring, address: uint64,
                        cond: BreakCond = bcExecute,
                        len:  BreakLen  = bl1,
                        local: bool    = true) =
  doAssert slot in 0 .. 3, "Debug slot must be in 0..=3" 
  gBreakpoints[slot] = Breakpoint(name: name, address: address,
                                  cond: cond, len: len, used: true)
  slotWriteAddr(slot, address)
  var dr7 = readDR7()
  dr7.bp[slot].cond   = cond
  dr7.bp[slot].len    = len
  dr7.bp[slot].local  = local
  dr7.bp[slot].global = false
  writeDR7(dr7)

proc installBreakpoint*(name: cstring, address: uint64,
                        cond: BreakCond = bcExecute,
                        len:  BreakLen  = bl1): int =
  ## Auto‑pick a free slot. Returns slot 0..3, or ‑1 if none free.
  for i in 0 .. 3:
    if not gBreakpoints[i].used:
      installBreakpoint(i, name, address, cond, len)
      return i
  return -1

proc removeBreakpoint*(slot: int) =
  doAssert slot in 0 .. 3
  var dr7 = readDR7()
  dr7.bp[slot].local  = false
  dr7.bp[slot].global = false
  writeDR7(dr7)
  gBreakpoints[slot] = Breakpoint()

proc removeAllBreakpoints*() =
  for i in 0 .. 3: removeBreakpoint(i)

proc isDumpRegs*() : bool {.inline.} = (gDebugFlags and ord dumpRegs) != 0
proc isDisasRip*() : bool {.inline.} = (gDebugFlags and ord disasRip) != 0
proc isDisasMany*(): bool {.inline.} = (gDebugFlags and ord disasMany) != 0

proc resetDebugFlags*() {.inline.} = gDebugFlags = 0

import drivers/output/vga

proc disasOne*(address: uint64) =
  var buf: array[MaxInsnLen, char]
  let p = cast[ptr UncheckedArray[uint8]](address)
  discard decode(address, p, buf)
  putHex address
  put ": "
  put cast[cstring](addr buf[0])

proc disasRange*(start: uint64, count: int) =
  var a = start
  var buf: array[MaxInsnLen, char]
  for _ in 0..<count:
    let p = cast[ptr UncheckedArray[uint8]](a)
    let len = decode(a, p, buf)
    putHex a
    put ":"
    put cast[cstring](addr buf[0])
    put "; "
    a += uint64(len)

proc dumpBytes*(address: uint64, n: int = 10) =
  let p = cast[ptr UncheckedArray[uint8]](address)
  for i in 0..<n:
    putHex uint64(p[i])
    put " "

proc disasAround*(address: uint64, before, after: int) =
  # Disassemble `before` instructions before and `after` after `address`.
  # Simplest reliable approach: scan backwards byte-by-byte and decode forward,
  # keeping the last window that lands exactly on `address`.
  #
  # For a debug helper we cheat: dump `after` instructions starting at address,
  # and dump a fixed byte window before it as raw bytes.
  var a = address
  var buf: array[MaxInsnLen, char]
  var oldCol = vgaW.color
  for _ in 0..<after:
    vgaW.color = oldCol
    if a == address:
      chCol Black, White
    let p = cast[ptr UncheckedArray[uint8]](a)
    let len = decode(a, p, buf)
    put "   "
    putHex a
    put ": "
    put cast[cstring](addr buf[0])
    put "\n"
    a += uint64(len)
