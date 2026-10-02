import arch/x86_64/port
import kstd/hooks

const
  COM1 = 0x3F8'u16

proc init() {.inline.} =
  outb(COM1 + 1, 0x00) # disable interrupts
  outb(COM1 + 3, 0x80) # enable DLAB
  outb(COM1 + 0, 0x03) # Baud rate divisor (lo byte) = 3 (38400 baud)
  outb(COM1 + 1, 0x00) #                   (hi byte)
  outb(COM1 + 3, 0x03) # 8 bits, no parity, one stop bit
  outb(COM1 + 2, 0xC7) # enable FIFO
  outb(COM1 + 4, 0x0B) # IRQs enabled, RTS/DSR set

proc ready*(): bool {.inline.} =
  result = (inb(COM1 + 5) and 0x20) != 0

proc putC*(c: char) {.inline.} =
  while not ready():
    discard
  COM1.outb uint8(c)
    
proc putS*(s: openArray[char]) =
  for c in s: putC c

proc putCString*(s: cstring) =
  var i = 0
  while s[i] != '\0':
    putC s[i]
    inc i

proc putHexDigit(n: uint8) {.inline.} =
  putC (if n < 10: char(ord('0') + n) else: char(ord('a') + n - 10))

proc putUintHex*(x: uint64) {.inline.} =
  var started = false
  for i in countdown(15, 0):
    let d = uint8((x shr (i * 4)) and 0xF'u64)
    if d != 0 or started or i == 0:
      started = true
      putHexDigit d

proc putHex*(x: uint64) {.inline.} =
  putS "0x"
  putUintHex x

proc putHexPadded*(x: uint64, digits: range[1..16]) =
  ## Fixed-width hex with leading zeros, no prefix.
  for i in countdown(digits - 1, 0):
    putHexDigit uint8((x shr (i * 4)) and 0xF'u64)

proc putHex*(x: uint32) {.inline.} = putHex uint64(x)
proc putHex*(x: uint16) {.inline.} = putHex uint64(x)
proc putHex*(x: uint8)  {.inline.} = putHex uint64(x)
proc putHex*(x: int)    {.inline.} = putHex cast[uint64](x)

proc putUint*(x: uint64) =
  if x == 0:
    putC '0'
    return
  var buf: array[20, char]       # uint64 max is 20 digits
  var i = buf.len
  var v = x
  while v > 0:
    dec i
    buf[i] = char(ord('0') + int(v mod 10))
    v = v div 10
  for j in i ..< buf.len:
    putC buf[j]

proc putInt*(x: int64) =
  if x < 0:
    putC '-'
    if x == low(int64):
      # |INT64_MIN| doesn't fit in int64; hardcode.
      putS "9223372036854775808"
      return
    putUint uint64(-x)
  else:
    putUint uint64(x)

proc putInt*(x: int32)  {.inline.} = putInt int64(x)
proc putInt*(x: int16)  {.inline.} = putInt int64(x)
proc putInt*(x: int8)   {.inline.} = putInt int64(x)
proc putInt*(x: int)    {.inline.} = putInt int64(x)
proc putInt*(x: uint64) {.inline.} = putUint x
proc putInt*(x: uint32) {.inline.} = putUint uint64(x)


# proc put*(p: string)   = putS p
proc put*(p: cstring)  = putCString p
proc put*(p: char)     = putC p
proc put*(p: bool)     = putS (if p: "true" else: "false")
proc put*(p: SomeUnsignedInt) = putUint uint64(p)
proc put*(p: SomeSignedInt)   = putInt int64(p)

import macros

template serialPut(p: typed) =
  bind put
  put p

template serialPutc(c: char) =
  bind putc
  putc c, w

macro print*(args: varargs[untyped]): untyped =
  result = newStmtList()
  let serialPut = bindSym("serialPut", brClosed)
  for a in args:
    result.add newCall(serialPut, a)

macro println*(args: varargs[untyped]): untyped =
  result = newStmtList()
  let serialPut  = bindSym("serialPut" , brClosed)
  let serialPutC = bindSym("serialPutc", brClosed)
  for a in args:
    result.add newCall(serialPut, a)
  result.add newCall(serialPutC, newLit('\n'))

proc putSpaces*(n: int) =
  for _ in 0 ..< n: putc ' '

proc putAscii*(b: uint8) =
  if b >= 0x20 and b < 0x7F: putc char(b)
  else: putc '.'

proc hexdump*(p: pointer, len: uint, label: cstring = nil) =
  if label != nil:
    put label
    putc '\n'
  if p == nil:
    put "<nil>\n"
    return
  var address = cast[uint64](p)
  var base = cast[uint64](p)
  var remaining = int(len)
  while remaining > 0:
    let n = if remaining < 16: remaining else: 16

    # address
    putHexPadded(address, 16)
    put("  ")

    # hex bytes
    for i in 0 ..< 16:
      if i < n:
        putHexPadded(cast[ptr UncheckedArray[uint8]](address)[i], 2)
      else:
        put("  ")
      putc(if i == 7: ' ' else: ' ')

    put("  |")

    # ascii
    for i in 0 ..< n:
      putAscii cast[ptr UncheckedArray[uint8]](address)[i]
    put("|\n")

    address += uint64(n)
    remaining -= n


initAppend:
  init()
