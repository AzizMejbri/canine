import ./interrupts/faults
import kstd/hooks

type
  Gate_Type* = enum
    Undefined = 0
    InterruptGate = 0b1110
    TrapGate = 0b1111
  
  Ring_Lvl* = enum
    Ring0 = 0b00
    Ring2 = 0b10
    Ring1 = 0b01
    Ring3 = 0b11

  Int_Desc_Entry* {.packed.} = object
    offsetLo:  uint16        ## offset bits 0..15
    selector:  uint16        ## code segment selector
    ist:       uint8         ## bits 0..2 = IST index, bits 3..7 = 0
    gateType:  uint8         ## bits 0..3 = gate type, bit 4 = 0,
                             ## bits 5..6 = DPL, bit 7 = present
    offsetMid: uint16        ## offset bits 16..31
    offsetHi:  uint32        ## offset bits 32..63
    reserved:  uint32 = 0

  Int_Desc_Ptr* {.packed.} = object
    limit: uint16
    base:  uint64 

static:
  doAssert sizeof(Int_Desc_Entry) == 16
  doAssert sizeof(Int_Desc_Ptr) == 10

var idt {.align(16).}: array[256, Int_Desc_Entry]
var idtp: Int_Desc_Ptr

proc load() {.inline.} =
  idtp.limit = uint16(sizeof(idt) - 1)
  idtp.base = cast[uint64](addr idt)
  let p = addr idtp
  asm """
    .intel_syntax noprefix
    lidt [rdi]
    .att_syntax
    :: "D" (`p`)
    : "memory"
  """

proc setEntry*(vec: uint8, handler: uint64 = 0'u64, sel: uint16 = 0'u16,
              gateType: Gate_Type = Undefined, ring: Ring_Lvl = Ring0, ist: uint8 = 0) {.inline.} =
  let flags =
    (uint8(ord(gateType)) and 0x0F) or
    ((uint8(ord(ring)) and 0x03) shl 5) or
    (1'u8 shl 7)                     # present = 1
  idt[vec] = Int_Desc_Entry(
    offsetLo:  uint16(handler and 0xFFFF),
    selector:  sel,
    ist:       ist,
    gateType:  flags,
    offsetMid: uint16((handler shr 16) and 0xFFFF),
    offsetHi:  uint32((handler shr 32) and 0xFFFFFFFF'u64),
  )


proc init() {.inline.} =
  let isrs: array[32, uint64] = [
    cast[uint64](isr0),  cast[uint64](isr1),  cast[uint64](isr2),  cast[uint64](isr3),
    cast[uint64](isr4),  cast[uint64](isr5),  cast[uint64](isr6),  cast[uint64](isr7),
    cast[uint64](isr8),  cast[uint64](isr9),  cast[uint64](isr10), cast[uint64](isr11),
    cast[uint64](isr12), cast[uint64](isr13), cast[uint64](isr14), cast[uint64](isr15),
    cast[uint64](isr16), cast[uint64](isr17), cast[uint64](isr18), cast[uint64](isr19),
    cast[uint64](isr20), cast[uint64](isr21), cast[uint64](isr22), cast[uint64](isr23),
    cast[uint64](isr24), cast[uint64](isr25), cast[uint64](isr26), cast[uint64](isr27),
    cast[uint64](isr28), cast[uint64](isr29), cast[uint64](isr30), cast[uint64](isr31),
  ]
  for i in 0 ..< 8:
    setEntry uint8(i), isrs[i], 0x08, InterruptGate, Ring0
  setEntry 8'u8, isrs[8], 0x08, InterruptGate, Ring0, ist = 1
  for i in 9 ..< 32:
    setEntry uint8(i), isrs[i], 0x08, InterruptGate, Ring0
  for i in 32 ..< 256:
    setEntry uint8(i)

initAppend:
  init()
  load()
