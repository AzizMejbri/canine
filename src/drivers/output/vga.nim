import kstd/option
import macros
import drivers/output/serial as com

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

proc flushCell(w: var Vga_Writer, row, col: int) {.inline.} =
  let idx = row * VGA_WIDTH + col
  let cell = w.buffer[row][col]
  VGA_MEM[idx] = uint16(cell.character) or (uint16(cell.color) shl 8)

proc flush*(w: var Vga_Writer = vgaW) =
  for row in 0 ..< VGA_HEIGHT:
    for col in 0 ..< VGA_WIDTH:
      flushCell(w, row, col)

proc scrollUp*(w: var Vga_Writer = vgaW) =
  for r in 0 ..< VGA_HEIGHT - 1:
    for c in 0 ..< VGA_WIDTH:
      w.buffer[r][c] = w.buffer[r + 1][c]
  let blank = Vga_Cell(character: uint8(' '), color: w.color)
  for c in 0 ..< VGA_WIDTH:
    w.buffer[VGA_HEIGHT - 1][c] = blank
  flush w

proc newline*(w: var Vga_Writer = vgaW) =
  var oldColor = w.color
  w.color = uint8(ord(LightGray) or (ord(Black) shl 4))
  w.cursorX = 0
  inc w.cursorY
  if w.cursorY >= VGA_HEIGHT:
    w.cursorY = VGA_HEIGHT - 1
    scrollUp w
  w.color = oldColor

proc clear*(w: var Vga_Writer = vgaW) =
  let blank = Vga_Cell(character: uint8(' '), color: attr(LightGray, Black))
  for r in 0 ..< VGA_HEIGHT:
    for c in 0 ..< VGA_WIDTH:
      w.buffer[r][c] = blank
  w.cursorX = 0
  w.cursorY = 0
  flush w

proc putc*(c: char, w: var Vga_Writer = vgaW) =
  if c == '\n':
    newline w
    return
  if c == '\t':
    putc(' ', w)
    putc(' ', w)
    return
  if c == char(8'u8):
    if w.cursorX > 0:
      dec w.cursorX
    elif w.cursorY > 0:
      dec w.cursorY
      w.cursorX = VGA_WIDTH - 1
    w.buffer[w.cursorY][w.cursorX] = Vga_Cell(character: uint8(' '), color: w.color)
    flushCell(w, w.cursorY, w.cursorX)
    return
  w.buffer[w.cursorY][w.cursorX] = Vga_Cell(character: uint8(c), color: w.color)
  flushCell(w, w.cursorY, w.cursorX)
  inc w.cursorX
  if w.cursorX >= VGA_WIDTH:
    newline w

proc puts*(s: openArray[char], w: var Vga_Writer = vgaW) =
  for c in s:
    putc(c, w)

proc puts*(s: cstring, w: var Vga_Writer = vgaW) =
  if s.isNil: return
  var p = cast[ptr UncheckedArray[char]](s)
  var i = 0
  while p[i] != '\0':
    putc p[i], w
    inc i

proc putHexDigit*(n: uint8, w: var Vga_Writer = vgaW) {.inline.} =
  putc(char(if n < 10: ord('0') + int(n) else: ord('a') + int(n) - 10), w)

proc putUintHex*(x: uint64, w: var Vga_Writer = vgaW) =
  var started = false
  for i in countdown(15, 0):
    let d = uint8((x shr (i * 4)) and 0xF'u64)
    if d != 0 or started or i == 0:
      started = true
      putHexDigit(d, w)

proc putHex*(x: uint64, w: var Vga_Writer = vgaW) =
  puts("0x", w)
  putUintHex(x, w)

proc putHexPadded*(x: uint64, digits: int, w: var Vga_Writer = vgaW) =
  ## Fixed-width hex, no prefix. `digits` in 1..16.
  var i = digits - 1
  while i >= 0:
    putHexDigit(uint8((x shr (i * 4)) and 0xF'u64), w)
    dec i

proc putHex*(x: uint32, w: var Vga_Writer = vgaW) {.inline.} = putHex(uint64(x), w)
proc putHex*(x: uint16, w: var Vga_Writer = vgaW) {.inline.} = putHex(uint64(x), w)
proc putHex*(x: uint8,  w: var Vga_Writer = vgaW) {.inline.} = putHex(uint64(x), w)
proc putHex*(x: int,    w: var Vga_Writer = vgaW) {.inline.} = putHex(cast[uint64](x), w)

proc putUint*(x: uint64, w: var Vga_Writer = vgaW) =
  if x == 0:
    putc('0', w)
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
    putc(buf[j], w)
    inc j

proc putInt*(x: int64, w: var Vga_Writer = vgaW) =
  if x < 0:
    putc('-', w)
    if x == low(int64):
      puts("9223372036854775808", w)
      return
    putUint(uint64(-x), w)
  else:
    putUint(uint64(x), w)

proc putInt*(x: int32,  w: var Vga_Writer = vgaW) {.inline.} = putInt(int64(x), w)
proc putInt*(x: int16,  w: var Vga_Writer = vgaW) {.inline.} = putInt(int64(x), w)
proc putInt*(x: int8,   w: var Vga_Writer = vgaW) {.inline.} = putInt(int64(x), w)
proc putInt*(x: int,    w: var Vga_Writer = vgaW) {.inline.} = putInt(int64(x), w)
proc putInt*(x: uint64, w: var Vga_Writer = vgaW) {.inline.} = putUint(x, w)
proc putInt*(x: uint32, w: var Vga_Writer = vgaW) {.inline.} = putUint(uint64(x), w)
proc putUint*(x: uint32, w: var Vga_Writer = vgaW) {.inline.} = putUint(uint64(x), w)
proc putUint*(x: uint16, w: var Vga_Writer = vgaW) {.inline.} = putUint(uint64(x), w)
proc putUint*(x: uint8,  w: var Vga_Writer = vgaW) {.inline.} = putUint(uint64(x), w)

converter toOptColor*(c: Vga_Color): Option[Vga_Color] {.inline.} =
  some c

const noColor* = none Vga_Color

proc chCol*(fg: Option[Vga_Color] = none(Vga_Color),
            bg: Option[Vga_Color] = none(Vga_Color),
            w: var Vga_Writer = vgaW) =
  let currFg = w.color and 0x0F'u8
  let currBg = (w.color shr 4) and 0x0F'u8
  let newFg = if fg.isSome: uint8(ord(fg.get)) else: currFg
  let newBg = if bg.isSome: uint8(ord(bg.get)) else: currBg
  w.color = newFg or (newBg shl 4)


template resetCol*(w: var Vga_Writer = vgaW) = chCol LightGray, Black, w

proc put*(p: static string,   w: var Vga_Writer = vgaW) = puts(p, w)
proc put*(p: openArray[char], w: var Vga_Writer = vgaW) = puts(p, w)
proc put*(p: cstring,         w: var Vga_Writer = vgaW) =
  var i = 0
  while p[i] != '\0':
    putc(p[i], w)
    inc i
proc put*(p: char,            w: var Vga_Writer = vgaW) = putc p, w
proc put*(p: bool,            w: var Vga_Writer = vgaW) = puts(if p: "true" else: "false", w)
proc put*(p: SomeUnsignedInt, w: var Vga_Writer = vgaW) = putUint uint64(p), w
proc put*(p: SomeSignedInt,   w: var Vga_Writer = vgaW) = putInt int64(p), w

template vgaPut(p: typed, w: var Vga_Writer = vgaW) =
  bind put
  put p, w

template vgaPutc(c: char, w: var Vga_Writer = vgaW) =
  bind putc
  putc c, w

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

proc setCursor*(x: int, y: int, w: var Vga_Writer = vgaW) =
  w.cursorX = x
  w.cursorY = y
