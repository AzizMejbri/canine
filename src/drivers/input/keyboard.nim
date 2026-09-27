import globals
import kstd/[hooks, mem, ringbuffer as rb, option]
import drivers/[pic, output/vga]
import arch/x86_64/[idt, ctrl]
import arch/x86_64/port


type
  Modifier* {.pure.} = enum
    LShift, RShift, LCtrl, RCtrl, LAlt, RAlt, CapsLock, NumLock, ScrollLock

  State* {.packed.} = object
    lshift {.bitsize: 1.}: uint8
    rshift {.bitsize: 1.}: uint8
    lctrl  {.bitsize: 1.}: uint8
    rctrl  {.bitsize: 1.}: uint8
    lalt   {.bitsize: 1.}: uint8
    ralt   {.bitsize: 1.}: uint8
    caps   {.bitsize: 1.}: uint8
    num    {.bitsize: 1.}: uint8
    scroll {.bitsize: 1.}: uint8

  Led* = enum
    LedScrollLock = 0x01
    LedNumLock    = 0x02
    LedCapsLock   = 0x04

  Layout* = object
    normal*: array[128, char]
    shift* :  array[128, char]

  SpecialKey* = enum
    skEsc, skBackspace, skEnter, skTab
    skF1, skF2, skF3, skF4, skF5, skF6, skF7, skF8, skF9, skF10, skF11, skF12
    skUp, skDown, skLeft, skRight
    skHome, skEnd, skPgUp, skPgDn
    skInsert, skDelete
    skKp0, skKp1, skKp2, skKp3, skKp4, skKp5, skKp6, skKp7, skKp8, skKp9
    skKpEnter, skKpPlus, skKpMinus, skKpStar, skKpSlash, skKpDot

  KeyKind* = enum
    kkChar, kkSpecial, kkModifier

  KeyEvent* = object
    pressed*: bool
    state*  :    State
    case kind*: KeyKind
    of kkChar    : ch*: char
    of kkSpecial : special*: SpecialKey
    of kkModifier: modifier*: Modifier

  Keyboard* = object
    layout*  : Layout
    state*   : State
    extended*: bool  # saw a 0xE0 field, next byte is extended

const
  DataPort*      = 0x60'u8
  CmdPort*       = 0x64'u8
  KbIrqLine*     = globals.IrqLines.keyboard
  KbIdtOffs*     = globals.IdtOffs.keyboard

  
  KeyNone        = 0x00'u8
  KeyEsc         = 0x01'u8
  KeyBackspace   = 0x0E'u8
  KeyTab*        = 0x0F'u8
  KeyEnter*      = 0x1C'u8
  KeyLCtrl*      = 0x1D'u8
  KeyLShift*     = 0x2A'u8
  KeyRShift*     = 0x36'u8
  KeyLAlt*       = 0x38'u8
  KeyCapsLock*   = 0x3A'u8
  KeyNumLock*    = 0x45'u8
  KeyScrollLock* = 0x46'u8
  KeyF1*         = 0x3B'u8
  KeyF2*         = 0x3C'u8
  KeyF3*         = 0x3D'u8
  KeyF4*         = 0x3E'u8
  KeyF5*         = 0x3F'u8
  KeyF6*         = 0x40'u8
  KeyF7*         = 0x41'u8
  KeyF8*         = 0x42'u8
  KeyF9*         = 0x43'u8
  KeyF10*        = 0x44'u8
  KeyF11*        = 0x57'u8
  KeyF12*        = 0x58'u8

  UsLayout* = Layout(
    normal: [
      '\0', '\e', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b', '\t',
      'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n', '\0',
      'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', '\0', '\\',
      'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', '\0', '*', '\0', ' ',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '7', '8', '9', '-',
      '4', '5', '6', '+', '1', '2', '3', '0', '.',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
    ],
    shift: [
      '\0', '\e', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\b', '\t',
      'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n', '\0',
      'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', '\0', '|',
      'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', '\0', '*', '\0', ' ',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '7', '8', '9', '-',
      '4', '5', '6', '+', '1', '2', '3', '0', '.',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
      '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0',
    ],
  )

var gKbd = Keyboard(layout: UsLayout)

proc updateLeds(self: var Keyboard) {.inline.} =
  var led: uint8 = 0
  if self.state.scroll != 0: led = led or uint8(ord LedScrollLock)
  if self.state.num    != 0: led = led or uint8(ord LedNumLock)
  if self.state.caps   != 0: led = led or uint8(ord LedCapsLock)

  outb(DataPort, 0xED)
  outb(DataPort, led)

proc setModifier(self: var Keyboard, m: Modifier, pressed: bool) {.inline.} =
  let v = if pressed: 1'u8 else: 0'u8
  case m
  of LShift: self.state.lshift = v
  of RShift: self.state.rshift = v
  of LCtrl:  self.state.lctrl  = v
  of RCtrl:  self.state.rctrl  = v
  of LAlt:   self.state.lalt   = v
  of RAlt:   self.state.ralt   = v
  of CapsLock:   self.state.caps   = v
  of NumLock:    self.state.num    = v
  of ScrollLock: self.state.scroll = v


proc kbHandler() {.noconv, asmNoStackFrame.}
proc enable() {.inline.} =
  clearMask(KbIrqLine)
  setEntry KbIdtOffs, cast[uint64](cast[pointer](kbHandler)), CodeSegmentSel, InterruptGate, Ring0


proc kbHandler() {.noconv, asmNoStackFrame.} =
  pushAll()
  asm "call kbd_isr_body"
  sendEOI KbIrqLine
  popAll()
  asm "iretq"

proc resolveChar(self: Keyboard, code: uint8): char {.inline.} =
  if code >= 128: return '\0'
  let shift = self.state.lshift or self.state.rshift
  var c = if shift != 0: self.layout.shift[code] else: self.layout.normal[code]
  if self.state.caps != 0:
    if c in {'a'..'z'}:   c = char(ord(c) - 32)
    elif c in {'A'..'Z'}: c = char(ord(c) + 32)
  c

proc handleModifier(self: var Keyboard, m: Modifier, released: bool): Option[KeyEvent] {.inline.} =
  case m
  of LShift, RShift, LCtrl, RCtrl, LAlt, RAlt:
    self.setModifier m, not released
    some KeyEvent(kind: kkModifier, pressed: not released, state: self.state, modifier: m)
  of CapsLock, NumLock, ScrollLock:
    if released: return none(KeyEvent)
    case m
    of CapsLock:   self.state.caps   = self.state.caps   xor 1
    of NumLock:    self.state.num    = self.state.num    xor 1
    of ScrollLock: self.state.scroll = self.state.scroll xor 1
    else: discard
    self.updateLeds()
    some KeyEvent(kind: kkModifier, pressed: true, state: self.state, modifier: m)

proc decodeExtended(self: var Keyboard, code: uint8, released: bool): Option[KeyEvent] {.inline.} =
  let p = not released
  case code
  of 0x1D: return self.handleModifier(RCtrl, released)
  of 0x38: return self.handleModifier(RAlt, released)
  of 0x1C: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skKpEnter)
  of 0x35: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skKpSlash)
  of 0x47: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skHome)
  of 0x48: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skUp)
  of 0x49: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skPgUp)
  of 0x4B: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skLeft)
  of 0x4D: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skRight)
  of 0x4F: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skEnd)
  of 0x50: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skDown)
  of 0x51: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skPgDn)
  of 0x52: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skInsert)
  of 0x53: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skDelete)
  else: return none(KeyEvent)

proc decodeNormal(self: var Keyboard, code: uint8, released: bool): Option[KeyEvent] {.inline.} =
  let p = not released
  case code
  of KeyLShift:     return self.handleModifier(LShift, released)
  of KeyRShift:     return self.handleModifier(RShift, released)
  of KeyLCtrl:      return self.handleModifier(LCtrl, released)
  of KeyLAlt:       return self.handleModifier(LAlt, released)
  of KeyCapsLock:   return self.handleModifier(CapsLock, released)
  of KeyNumLock:    return self.handleModifier(NumLock, released)
  of KeyScrollLock: return self.handleModifier(ScrollLock, released)
  else: discard

  case code
  of KeyEsc:       return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skEsc)
  of KeyBackspace: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skBackspace)
  of KeyTab:       return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skTab)
  of KeyEnter:     return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skEnter)
  of KeyF1:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF1)
  of KeyF2:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF2)
  of KeyF3:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF3)
  of KeyF4:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF4)
  of KeyF5:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF5)
  of KeyF6:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF6)
  of KeyF7:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF7)
  of KeyF8:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF8)
  of KeyF9:  return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF9)
  of KeyF10: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF10)
  of KeyF11: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF11)
  of KeyF12: return some KeyEvent(kind: kkSpecial, pressed: p, state: self.state, special: skF12)
  else: discard

  let c = self.resolveChar(code)
  if c == '\0': return none(KeyEvent)
  some KeyEvent(kind: kkChar, pressed: p, state: self.state, ch: c)

proc decodeScancode(self: var Keyboard, sc: uint8): Option[KeyEvent] {.inline.} =
  if sc == 0xE0:                # extended prefix
    self.extended = true
    return none(KeyEvent)
  if sc == 0xE1:                # Pause — not decoded
    return none(KeyEvent)

  let ext = self.extended
  self.extended = false
  let released = (sc and 0x80) != 0
  let code     = sc and 0x7F

  if ext: self.decodeExtended(code, released)
  else:   self.decodeNormal(code, released)


var kbdRb = rb.init[KeyEvent, 256]()

proc kbIsrBody() {.exportc: "kbd_isr_body", cdecl, used.} =
  let sc = inb DataPort
  let ev = decodeScancode(gKbd, sc)
  if ev.isSome: kbdRb.push ev.get
  # if ev.isNone: return
  # let e = ev.get
  # case e.kind
  # of kkChar:
  #   if e.pressed:
  #     setCursor 0, 1
  #     print "[LOG] pressed: "
  #     {.push checks:off.}
  #     println e.ch
  #     {.pop.}
  #   else:
  #     setCursor 0, 1
  #     println "[LOG] released"
  # else: discard



# -------------- public API -----------------------
proc readKey*(): Option[KeyEvent] {.inline.} =
  kbdRb.pop()

iterator keys*(): KeyEvent =
  for e in kbdRb.drain:
    yield e

# Text-only convenience — filters for you
proc readChar*(): Option[char] {.inline.} =
  while true:
    let ev = kbdRb.pop()
    if ev.isNone: return none(char)
    let e = ev.get
    case e.kind
    of kkChar:
      if e.pressed: return some e.ch
    of kkSpecial, kkModifier: discard

initAppend 130:
  enable()
