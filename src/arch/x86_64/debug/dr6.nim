import std/bitops
import arch/arch_specific
import arch/x86_64/debug/raw

type DR6* = object
  b0*, b1*, b2*, b3*: bool   ## breakpoint 0..3 condition met
  bd*, bs*, bt*: bool        ## debug-reg access / single-step / task-switch
  rtm*: bool                 ## false ⇒ exception occurred inside an RTM region

proc toU64*(d: DR6): uint64 {.inline.} =
  if d.b0:  result.setBit 0
  if d.b1:  result.setBit 1
  if d.b2:  result.setBit 2
  if d.b3:  result.setBit 3
  if d.bd:  result.setBit 13
  if d.bs:  result.setBit 14
  if d.bt:  result.setBit 15
  if d.rtm: result.setBit 16

proc fromU64*(T: typedesc[DR6], v: uint64): DR6 {.inline.} =
  DR6(
    b0:  v.testBit 0,  b1:  v.testBit 1,
    b2:  v.testBit 2,  b3:  v.testBit 3,
    bd:  v.testBit 13, bs:  v.testBit 14,
    bt:  v.testBit 15, rtm: v.testBit 16,
  )

proc readDR6*(): DR6 {.inline, x86_64.} =
  DR6.fromU64(rawReadDR6())

proc writeDR6*(d: DR6) {.inline, x86_64.} =
  ## Writing 1 leaves a sticky status bit unchanged; writing 0 clears it.
  ## To fully clear DR6, `writeDR6(default(DR6))`.
  rawWriteDR6(d.toU64)
