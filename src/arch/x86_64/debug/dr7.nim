import std/bitops
import arch/arch_specific
import arch/x86_64/debug/raw

type
  BreakCond* = enum
    bcExecute = 0b00
    bcWrite   = 0b01
    bcIo      = 0b10
    bcRW      = 0b11

  BreakLen* = enum
    bl1 = 0b00
    bl2 = 0b01
    bl8 = 0b10     ## NOTE: ord != size; bl8 has a lower ord than bl4
    bl4 = 0b11

  BP7* = object
    local*, global*: bool
    cond*: BreakCond
    len*:  BreakLen

  DR7* = object
    bp*:  array[4, BP7]
    rtm*: bool     ## bit 11, TSX only
    gd*:  bool     ## bit 13, general detect (fault on any DR access)

proc toU64*(d: DR7): uint64 {.inline.} =
  for i in 0 .. 3:
    if d.bp[i].local:  result.setBit (2*i)
    if d.bp[i].global: result.setBit (2*i + 1)
    result = result or (uint64(ord(d.bp[i].cond)) shl (16 + 4*i))
    result = result or (uint64(ord(d.bp[i].len))  shl (18 + 4*i))
  if d.rtm: result.setBit 11
  if d.gd:  result.setBit 13

proc fromU64*(T: typedesc[DR7], v: uint64): DR7 {.inline.} =
  for i in 0 .. 3:
    result.bp[i].local  = v.testBit (2*i)
    result.bp[i].global = v.testBit (2*i + 1)
    result.bp[i].cond   = BreakCond((v shr (16 + 4*i)) and 0b11'u64)
    result.bp[i].len    = BreakLen ((v shr (18 + 4*i)) and 0b11'u64)
  result.rtm = v.testBit 11
  result.gd  = v.testBit 13


proc readDR7*(): DR7 {.inline, x86_64.} =
  DR7.fromU64(rawReadDR7())

proc writeDR7*(d: DR7) {.inline, x86_64.} =
  ## Bit 10 must be 1 on write; other reserved bits are zero in toU64.
  var raw = d.toU64
  raw.setBit 10
  rawWriteDR7(raw)
