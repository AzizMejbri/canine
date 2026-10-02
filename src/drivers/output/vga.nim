import macros

const
  VGA_WIDTH*  = 80
  VGA_HEIGHT* = 25

var VGA_MEM* = cast[ptr UncheckedArray[uint16]](0xB8000)

type
  Vga_Color* = enum
    Black = 0, Blue, Green, Cyan, Red, Magenta, Yellow, LightGray,
    DarkGray, LightBlue, LightGreen, LightCyan, LightRed, LightMagenta,
    LightYellow, White

  Vga_Cell* = object
    character*: uint8
    color*: uint8

proc attr*(fg, bg: Vga_Color): uint8 {.inline.} =
  uint8(ord(fg)) or (uint8(ord(bg)) shl 4)

type
  Vga_Writer* = object
    buffer*: array[VGA_HEIGHT, array[VGA_WIDTH, Vga_Cell]]
    cursorX*: int
    cursorY*: int
    color*: uint8 = attr(LightGray, Black)

var vgaW*: Vga_Writer

proc flushCell(row, col: int) {.inline.} =
  let idx = row * VGA_WIDTH + col
  let cell = vgaW.buffer[row][col]
  VGA_MEM[idx] = uint16(cell.character) or (uint16(cell.color) shl 8)

proc flush*() =
  for row in 0 ..< VGA_HEIGHT:
    for col in 0 ..< VGA_WIDTH:
      flushCell(row, col)

proc scrollUp*() =
  for r in 0 ..< VGA_HEIGHT - 1:
    for c in 0 ..< VGA_WIDTH:
      vgaW.buffer[r][c] = vgaW.buffer[r + 1][c]
  let blank = Vga_Cell(character: uint8(' '), color: vgaW.color)
  for c in 0 ..< VGA_WIDTH:
    vgaW.buffer[VGA_HEIGHT - 1][c] = blank
  flush()

proc newline*() =
  var oldColor = vgaW.color
  vgaW.color = uint8(ord(LightGray) or (ord(Black) shl 4))
  vgaW.cursorX = 0
  inc vgaW.cursorY
  if vgaW.cursorY >= VGA_HEIGHT:
    vgaW.cursorY = VGA_HEIGHT - 1
    scrollUp()
  vgaW.color = oldColor

proc clear*() =
  let blank = Vga_Cell(character: uint8(' '), color: attr(LightGray, Black))
  for r in 0 ..< VGA_HEIGHT:
    for c in 0 ..< VGA_WIDTH:
      vgaW.buffer[r][c] = blank
  vgaW.cursorX = 0
  vgaW.cursorY = 0
  flush()

proc putc*(c: char) =
  if c == '\n':
    newline()
    return
  if c == '\t':
    putc(' ')
    putc(' ')
    return
  if c == char(8'u8):
    if vgaW.cursorX > 0:
      dec vgaW.cursorX
    elif vgaW.cursorY > 0:
      dec vgaW.cursorY
      vgaW.cursorX = VGA_WIDTH - 1
    vgaW.buffer[vgaW.cursorY][vgaW.cursorX] = Vga_Cell(character: uint8(' '), color: vgaW.color)
    flushCell(vgaW.cursorY, vgaW.cursorX)
    return
  vgaW.buffer[vgaW.cursorY][vgaW.cursorX] = Vga_Cell(character: uint8(c), color: vgaW.color)
  flushCell(vgaW.cursorY, vgaW.cursorX)
  inc vgaW.cursorX
  if vgaW.cursorX >= VGA_WIDTH:
    newline()

proc puts*(s: openArray[char]) =
  for c in s:
    putc(c)

proc puts*(s: cstring) =
  if s.isNil: return
  var p = cast[ptr UncheckedArray[char]](s)
  var i = 0
  while p[i] != '\0':
    putc(p[i])
    inc i

proc putHexDigit*(n: uint8) {.inline.} =
  putc(char(if n < 10: ord('0') + int(n) else: ord('a') + int(n) - 10))

proc putUintHex*(x: uint64) =
  var started = false
  for i in countdown(15, 0):
    let d = uint8((x shr (i * 4)) and 0xF'u64)
    if d != 0 or started or i == 0:
      started = true
      putHexDigit(d)

proc putHex*(x: uint64) =
  puts("0x")
  putUintHex(x)

proc putHexPadded*(x: uint64, digits: int) =
  ## Fixed-width hex, no prefix. `digits` in 1..16.
  var i = digits - 1
  while i >= 0:
    putHexDigit(uint8((x shr (i * 4)) and 0xF'u64))
    dec i

proc putHex*(x: uint32) {.inline.} = putHex(uint64(x))
proc putHex*(x: uint16) {.inline.} = putHex(uint64(x))
proc putHex*(x: uint8)  {.inline.} = putHex(uint64(x))
proc putHex*(x: int)    {.inline.} = putHex(cast[uint64](x))

proc putUint*(x: uint64) =
  if x == 0:
    putc('0')
    return
  var buf: array[20, char]
  var i = buf.len
  var v = x
  while v > 0:
    dec i
    buf[i] = char(ord('0') + int(v mod 10))
    v = v div 10
  var j = i
  while j < buf.len:
    putc(buf[j])
    inc j

proc putInt*(x: int64) =
  if x < 0:
    putc('-')
    if x == low(int64):
      puts("9223372036854775808")
      return
    putUint(uint64(-x))
  else:
    putUint(uint64(x))

proc putInt*(x: int32)   {.inline.} = putInt(int64(x))
proc putInt*(x: int16)   {.inline.} = putInt(int64(x))
proc putInt*(x: int8)    {.inline.} = putInt(int64(x))
proc putInt*(x: int)     {.inline.} = putInt(int64(x))
proc putInt*(x: uint64)  {.inline.} = putUint(x)
proc putInt*(x: uint32)  {.inline.} = putUint(uint64(x))
proc putUint*(x: uint32) {.inline.} = putUint(uint64(x))
proc putUint*(x: uint16) {.inline.} = putUint(uint64(x))
proc putUint*(x: uint8)  {.inline.} = putUint(uint64(x))

proc chCol*(fg: Vga_Color, bg: Vga_Color) =
  let newFg = uint8(ord fg)
  let newBg = uint8(ord bg)
  vgaW.color = newFg or (newBg shl 4)

proc chFg*(fg: Vga_Color) =
  let newFg = uint8(ord fg)
  vgaW.color = vgaW.color and newFg

proc chBg*(bg: Vga_Color) =
  let newBg = uint8(ord bg)
  vgaW.color = vgaW.color and (newBg shl 4)

template resetCol*() = chCol LightGray, Black

proc put*(p: openArray[char]) = puts(p)
proc put*(p: cstring) =
  var i = 0
  while p[i] != '\0':
    putc(p[i])
    inc i
proc put*(p: char)            = putc p
proc put*(p: SomeUnsignedInt) = putUint uint64(p)
proc put*(p: SomeSignedInt)   = putInt int64(p)
proc put*(p: bool) =
  if p: put "true" else: put "false"

template vgaPut(p: typed) =
  bind put
  put p

template vgaPutc(c: char) =
  bind putc
  putc c

macro print*(args: varargs[untyped]): untyped =
  result = newStmtList()
  let vgaPut = bindSym("vgaPut", brClosed)
  for a in args:
    result.add newCall(vgaPut, a)

macro println*(args: varargs[untyped]): untyped =
  result = newStmtList()
  let vgaPut  = bindSym("vgaPut" , brClosed)
  let vgaPutC = bindSym("vgaPutC", brClosed)
  for a in args:
    result.add newCall(vgaPut, a)
  result.add newCall(vgaPutC, newLit('\n'))

proc setCursor*(x: int, y: int) =
  vgaW.cursorX = x
  vgaW.cursorY = y

proc putSpaces*(n: int) =
  for _ in 0 ..< n: putc ' '

proc putAscii*(b: uint8) =
  if b >= 0x20 and b < 0x7F: putc char(b)
  else: putc '.'

proc hexdump*(p: pointer, len: uint, label: cstring = nil) =
  if label != nil:
    puts label
    putc '\n'
  if p == nil:
    puts "<nil>\n"
    return
  var address = cast[uint64](p)
  var base = cast[uint64](p)
  var remaining = int(len)
  while remaining > 0:
    let n = if remaining < 16: remaining else: 16

    # address
    putHexPadded(address, 16)
    puts("  ")

    # hex bytes
    for i in 0 ..< 16:
      if i < n:
        putHexPadded(cast[ptr UncheckedArray[uint8]](address)[i], 2)
      else:
        puts("  ")
      putc(if i == 7: ' ' else: ' ')

    puts("  |")

    # ascii
    for i in 0 ..< n:
      putAscii cast[ptr UncheckedArray[uint8]](address)[i]
    puts("|\n")

    address += uint64(n)
    remaining -= n
