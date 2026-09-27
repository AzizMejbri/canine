## Minimal x86_64 disassembler for kernel debug output.
##
## Scope: subset emitted by clang/gcc for freestanding kernel code.
## Unknown bytes render as `db 0xXX` (length = 1). Never raises.
## Uses only fixed buffers — compatible with --mm:none.

const
  MaxInsnLen* = 128

  R8:  array[16, cstring] = ["al","cl","dl","bl","spl","bpl","sil","dil",
       "r8b","r9b","r10b","r11b","r12b","r13b","r14b","r15b"]
  R8H: array[4, cstring]  = ["ah","ch","dh","bh"]
  R16: array[16, cstring] = ["ax","cx","dx","bx","sp","bp","si","di",
       "r8w","r9w","r10w","r11w","r12w","r13w","r14w","r15w"]
  R32: array[16, cstring] = ["eax","ecx","edx","ebx","esp","ebp","esi","edi",
       "r8d","r9d","r10d","r11d","r12d","r13d","r14d","r15d"]
  R64: array[16, cstring] = ["rax","rcx","rdx","rbx","rsp","rbp","rsi","rdi",
       "r8","r9","r10","r11","r12","r13","r14","r15"]

  CC:     array[16, cstring] = ["o","no","b","ae","e","ne","be","a",
                                "s","ns","p","np","l","ge","le","g"]
  JCC:    array[16, cstring] = ["jo","jno","jb","jae","je","jne","jbe","ja",
                                "js","jns","jp","jnp","jl","jge","jle","jg"]
  CMOVCC: array[16, cstring] = ["cmovo","cmovno","cmovb","cmovae",
                                "cmove","cmovne","cmovbe","cmova",
                                "cmovs","cmovns","cmovp","cmovnp",
                                "cmovl","cmovge","cmovle","cmovg"]
  SETCC:  array[16, cstring] = ["seto","setno","setb","setae",
                                "sete","setne","setbe","seta",
                                "sets","setns","setp","setnp",
                                "setl","setge","setle","setg"]

proc regName(size: int, idx: int, hasRex: bool = true): cstring =
  case size
  of 1:
    if not hasRex and idx in 4..7: R8H[idx - 4] else: R8[idx]
  of 2: R16[idx]
  of 4: R32[idx]
  of 8: R64[idx]
  else: "?"

proc writeHex(buf: var array[MaxInsnLen, char], pos: int, v: uint64,
              minDigits: int = 1): int =
  const d = "0123456789abcdef"
  var tmp: array[16, char]
  var i = 16
  var x = v
  var m = minDigits
  while x != 0 or m > 0:
    dec i
    tmp[i] = d[int(x and 0xF)]
    x = x shr 4
    dec m
  var p = pos
  for j in i ..< 16:
    if p < MaxInsnLen - 1:
      buf[p] = tmp[j]
      inc p
  result = p

proc writeStr(buf: var array[MaxInsnLen, char], pos: int, s: cstring): int =
  var p = pos
  var i = 0
  while s[i] != '\0' and p < MaxInsnLen - 1:
    buf[p] = s[i]
    inc p
    inc i
  result = p

proc writeChar(buf: var array[MaxInsnLen, char], pos: int, c: char): int =
  if pos < MaxInsnLen - 1:
    buf[pos] = c
    result = pos + 1
  else:
    result = pos

proc s8(v: uint8):  int64 = int64(cast[int8](v))
proc s32(v: uint32): int64 = int64(cast[int32](v))

type
  Dec = object
    c: ptr UncheckedArray[uint8]
    p: int
    address: uint64
    rex: uint8
    hasRex: bool
    osz16: bool
    lock: bool
    rep: uint8
    seg: uint8

proc u8(d: var Dec): uint8 = (result = d.c[d.p]; inc d.p)
proc u16(d: var Dec): uint16 =
  result = uint16(d.c[d.p]) or (uint16(d.c[d.p+1]) shl 8); d.p += 2
proc u32(d: var Dec): uint32 =
  result = uint32(d.c[d.p]) or (uint32(d.c[d.p+1]) shl 8) or
           (uint32(d.c[d.p+2]) shl 16) or (uint32(d.c[d.p+3]) shl 24)
  d.p += 4
proc u64(d: var Dec): uint64 =
  result = uint64(d.u32()) or (uint64(d.u32()) shl 32)

proc modrm(d: var Dec, opsz: int, reg: var int,
           buf: var array[MaxInsnLen, char], pos: int): int =
  let m = d.u8()
  let modVal = (m shr 6) and 3
  reg = int(((m shr 3) and 7) or (if (d.rex and 4) != 0: 8 else: 0))
  let rm = int((m and 7) or (if (d.rex and 1) != 0: 8 else: 0))

  if modVal == 3:
    return writeStr(buf, pos, regName(opsz, rm, d.hasRex))

  var p = pos
  var disp: int64 = 0
  var haveDisp = false
  var haveBase = false

  if rm == 4:
    let sib = d.u8()
    let scale = 1 shl ((sib shr 6) and 3)
    let idx = int(((sib shr 3) and 7) or (if (d.rex and 2) != 0: 8 else: 0))
    let base = int((sib and 7) or (if (d.rex and 1) != 0: 8 else: 0))
    if (sib and 7) == 5 and modVal == 0:
      haveDisp = true
      disp = s32(d.u32())
    else:
      p = writeStr(buf, p, regName(8, base, d.hasRex))
      haveBase = true
    let idxValid = not (idx == 4 and (d.rex and 2) == 0)
    if idxValid:
      if haveBase: p = writeChar(buf, p, '+')
      p = writeStr(buf, p, regName(8, idx, d.hasRex))
      if scale > 1:
        p = writeChar(buf, p, '*')
        p = writeHex(buf, p, uint64(scale))
  elif rm == 5 and modVal == 0:
    let rel = s32(d.u32())
    let target = d.address + uint64(d.p) + uint64(rel)
    p = writeStr(buf, p, "0x")
    p = writeHex(buf, p, target, 1)
    return p
  else:
    p = writeStr(buf, p, regName(8, rm, d.hasRex))
    haveBase = true

  if modVal == 1:
    haveDisp = true; disp = s8(d.u8())
  elif modVal == 2:
    haveDisp = true; disp = s32(d.u32())

  if haveDisp:
    if disp < 0:
      p = writeStr(buf, p, "-0x")
      p = writeHex(buf, p, uint64(-disp))
    elif haveBase:
      p = writeStr(buf, p, "+0x")
      p = writeHex(buf, p, uint64(disp))
    else:
      p = writeStr(buf, p, "0x")
      p = writeHex(buf, p, uint64(disp))

  result = p

proc decode*(address: uint64, code: ptr UncheckedArray[uint8],
             outBuf: var array[MaxInsnLen, char]): int =
  var d = Dec(c: code, address: address)

  # prefixes
  while true:
    case d.c[d.p]
    of 0x66: d.osz16 = true; inc d.p
    of 0x67: inc d.p
    of 0xF0: d.lock = true; inc d.p
    of 0xF2, 0xF3: d.rep = d.c[d.p]; inc d.p
    of 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65: d.seg = d.c[d.p]; inc d.p
    of 0x40..0x4F: d.rex = d.c[d.p]; d.hasRex = true; inc d.p
    else: break

  let opsz =
    if (d.rex and 8) != 0: 8
    elif d.osz16: 2
    else: 4

  var mnem: cstring = ""
  var opsBuf: array[MaxInsnLen, char]
  var p = 0

  let op = d.u8()

  if op <= 0x3F and (op and 7) <= 5:
    let grp  = (op shr 3) and 7
    let form = op and 7
    const NAMES: array[8, cstring] =
      ["add","or","adc","sbb","and","sub","xor","cmp"]
    mnem = NAMES[grp]
    var reg: int
    case form
    of 0:
      p = modrm(d, 1, reg, opsBuf, p)
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(1, reg, d.hasRex))
    of 1:
      p = modrm(d, opsz, reg, opsBuf, p)
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
    of 2:
      p = modrm(d, 1, reg, opsBuf, p)
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(1, reg, d.hasRex))
    of 3:
      p = modrm(d, opsz, reg, opsBuf, p)
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
    of 4:
      p = writeStr(opsBuf, p, "al, 0x")
      p = writeHex(opsBuf, p, uint64(d.u8()))
    of 5:
      let imm = if opsz == 2: uint64(d.u16()) else: uint64(d.u32())
      p = writeStr(opsBuf, p, regName(opsz, 0, d.hasRex))
      p = writeStr(opsBuf, p, ", 0x")
      p = writeHex(opsBuf, p, imm)
    else: discard
  else:
    case op
    of 0x50..0x57:
      mnem = "push"
      p = writeStr(opsBuf, p, regName(8, int(op and 7) or (if (d.rex and 1) != 0: 8 else: 0)))
    of 0x58..0x5F:
      mnem = "pop"
      p = writeStr(opsBuf, p, regName(8, int(op and 7) or (if (d.rex and 1) != 0: 8 else: 0)))
    of 0x63:
      var reg: int
      p = modrm(d, 4, reg, opsBuf, p)
      mnem = "movsxd"
      p = writeStr(opsBuf, p, regName(if opsz == 8: 8 else: 4, reg, d.hasRex))
      p = writeStr(opsBuf, p, ", ")
      p = modrm(d, 4, reg, opsBuf, p)
    of 0x68:
      mnem = "push"
      p = writeStr(opsBuf, p, "0x")
      p = writeHex(opsBuf, p, uint64(d.u32()))
    of 0x69, 0x6B:
      var reg: int
      p = modrm(d, opsz, reg, opsBuf, p)
      mnem = "imul"
      p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
      p = writeStr(opsBuf, p, ", ")
      p = modrm(d, opsz, reg, opsBuf, p)
      p = writeStr(opsBuf, p, ", 0x")
      let imm = if op == 0x6B: uint64(d.u8())
                elif opsz == 2: uint64(d.u16())
                else: uint64(d.u32())
      p = writeHex(opsBuf, p, imm)
    of 0x70..0x7F:
      let rel = s8(d.u8())
      mnem = JCC[op and 0xF]
      p = writeStr(opsBuf, p, "0x")
      p = writeHex(opsBuf, p, d.address + uint64(d.p) + uint64(rel))
    of 0x80, 0x81, 0x83:
      var reg: int
      let sz = if op == 0x80: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      const NAMES: array[8, cstring] =
        ["add","or","adc","sbb","and","sub","xor","cmp"]
      mnem = NAMES[reg]
      p = writeStr(opsBuf, p, ", 0x")
      let imm = if op == 0x83: uint64(d.u8())
                elif sz == 2: uint64(d.u16())
                elif sz == 1: uint64(d.u8())
                else: uint64(d.u32())
      p = writeHex(opsBuf, p, imm)
    of 0x84, 0x85:
      var reg: int
      let sz = if op == 0x84: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      mnem = "test"
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(sz, reg, d.hasRex))
    of 0x86, 0x87:
      var reg: int
      let sz = if op == 0x86: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      mnem = "xchg"
      p = writeStr(opsBuf, p, ", ")
      p = writeStr(opsBuf, p, regName(sz, reg, d.hasRex))
    of 0x88, 0x89, 0x8A, 0x8B:
      var reg: int
      let is8 = (op and 1) == 0
      let sz = if is8: 1 else: opsz
      mnem = "mov"
      if op == 0x88 or op == 0x89:
        p = modrm(d, sz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, ", ")
        p = writeStr(opsBuf, p, regName(sz, reg, d.hasRex))
      else:
        p = modrm(d, sz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, regName(sz, reg, d.hasRex))
        p = writeStr(opsBuf, p, ", ")
        p = modrm(d, sz, reg, opsBuf, p)
    of 0x8D:
      var reg: int
      p = modrm(d, opsz, reg, opsBuf, p)
      mnem = "lea"
      p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
      p = writeStr(opsBuf, p, ", ")
      p = modrm(d, opsz, reg, opsBuf, p)
    of 0x8F:
      var reg: int
      p = modrm(d, 8, reg, opsBuf, p)
      mnem = "pop"
    of 0x90:
      if (d.rex and 1) != 0:
        mnem = "xchg"; p = writeStr(opsBuf, p, "r8, rax")
      else:
        mnem = "nop"
    of 0x98: mnem = (if opsz == 8: "cdqe" elif opsz == 2: "cbw" else: "cwde")
    of 0x99: mnem = (if opsz == 8: "cqo"  elif opsz == 2: "cwd" else: "cdq")
    of 0xA8:
      mnem = "test"
      p = writeStr(opsBuf, p, "al, 0x")
      p = writeHex(opsBuf, p, uint64(d.u8()))
    of 0xA9:
      let imm = if opsz == 2: uint64(d.u16()) else: uint64(d.u32())
      mnem = "test"
      p = writeStr(opsBuf, p, regName(opsz, 0, d.hasRex))
      p = writeStr(opsBuf, p, ", 0x")
      p = writeHex(opsBuf, p, imm)
    of 0xB0..0xB7:
      mnem = "mov"
      p = writeStr(opsBuf, p, regName(1, int(op and 7) or (if (d.rex and 1) != 0: 8 else: 0), d.hasRex))
      p = writeStr(opsBuf, p, ", 0x")
      p = writeHex(opsBuf, p, uint64(d.u8()))
    of 0xB8..0xBF:
      let reg = int(op and 7) or (if (d.rex and 1) != 0: 8 else: 0)
      mnem = "mov"
      if opsz == 8:
        p = writeStr(opsBuf, p, regName(8, reg))
        p = writeStr(opsBuf, p, ", 0x")
        p = writeHex(opsBuf, p, d.u64(), 1)
      elif opsz == 2:
        p = writeStr(opsBuf, p, regName(2, reg))
        p = writeStr(opsBuf, p, ", 0x")
        p = writeHex(opsBuf, p, uint64(d.u16()))
      else:
        p = writeStr(opsBuf, p, regName(4, reg))
        p = writeStr(opsBuf, p, ", 0x")
        p = writeHex(opsBuf, p, uint64(d.u32()))
    of 0xC0, 0xC1:
      var reg: int
      let sz = if op == 0xC0: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      const SH: array[8, cstring] =
        ["rol","ror","rcl","rcr","shl","shr","sal","sar"]
      mnem = SH[reg]
      p = writeStr(opsBuf, p, ", 0x")
      p = writeHex(opsBuf, p, uint64(d.u8()))
    of 0xC3: mnem = "ret"
    of 0xC6, 0xC7:
      var reg: int
      let sz = if op == 0xC6: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      mnem = "mov"
      p = writeStr(opsBuf, p, ", 0x")
      let imm = if sz == 1: uint64(d.u8())
                elif sz == 2: uint64(d.u16())
                else: uint64(d.u32())
      p = writeHex(opsBuf, p, imm)
    of 0xC9: mnem = "leave"
    of 0xCC: mnem = "int3"
    of 0xE8:
      let rel = s32(d.u32())
      mnem = "call"
      p = writeStr(opsBuf, p, "0x")
      p = writeHex(opsBuf, p, d.address + uint64(d.p) + uint64(rel))
    of 0xE9:
      let rel = s32(d.u32())
      mnem = "jmp"
      p = writeStr(opsBuf, p, "0x")
      p = writeHex(opsBuf, p, d.address + uint64(d.p) + uint64(rel))
    of 0xEB:
      let rel = s8(d.u8())
      mnem = "jmp"
      p = writeStr(opsBuf, p, "0x")
      p = writeHex(opsBuf, p, d.address + uint64(d.p) + uint64(rel))
    of 0xF4: mnem = "hlt"
    of 0xF6, 0xF7:
      var reg: int
      let sz = if op == 0xF6: 1 else: opsz
      p = modrm(d, sz, reg, opsBuf, p)
      case reg
      of 0:
        mnem = "test"
        p = writeStr(opsBuf, p, ", 0x")
        let imm = if sz == 1: uint64(d.u8())
                  elif sz == 2: uint64(d.u16())
                  else: uint64(d.u32())
        p = writeHex(opsBuf, p, imm)
      of 2: mnem = "not"
      of 3: mnem = "neg"
      of 4: mnem = "mul"
      of 5: mnem = "imul"
      of 6: mnem = "div"
      of 7: mnem = "idiv"
      else: discard
    of 0xFA: mnem = "cli"
    of 0xFB: mnem = "sti"
    of 0xFE:
      var reg: int
      p = modrm(d, 1, reg, opsBuf, p)
      case reg
      of 0: mnem = "inc"
      of 1: mnem = "dec"
      else: discard
    of 0xFF:
      var reg: int
      p = modrm(d, opsz, reg, opsBuf, p)
      case reg
      of 0: mnem = "inc"
      of 1: mnem = "dec"
      of 2: mnem = "call"
      of 4: mnem = "jmp"
      of 6: mnem = "push"
      else: discard
    of 0x0F:
      let op2 = d.u8()
      case op2
      of 0x05: mnem = "syscall"
      of 0x0B: mnem = "ud2"
      of 0x1E:
        if d.rep == 0xF3:
          discard d.u8()
          mnem = "endbr64"
        else:
          mnem = "nop"
      of 0x1F:
        var reg: int
        discard modrm(d, opsz, reg, opsBuf, p)
        mnem = "nop"
      of 0x20:
        let m = d.u8()
        let cr = (m shr 3) and 7
        let rr = int(m and 7) or (if (d.rex and 1) != 0: 8 else: 0)
        mnem = "mov"
        p = writeStr(opsBuf, p, regName(8, rr))
        p = writeStr(opsBuf, p, ", cr")
        p = writeHex(opsBuf, p, uint64(cr))
      of 0x22:
        let m = d.u8()
        let cr = (m shr 3) and 7
        let rr = int(m and 7) or (if (d.rex and 1) != 0: 8 else: 0)
        mnem = "mov"
        p = writeStr(opsBuf, p, "cr")
        p = writeHex(opsBuf, p, uint64(cr))
        p = writeStr(opsBuf, p, ", ")
        p = writeStr(opsBuf, p, regName(8, rr))
      of 0x30: mnem = "wrmsr"
      of 0x31: mnem = "rdtsc"
      of 0x32: mnem = "rdmsr"
      of 0x40..0x4F:
        var reg: int
        mnem = CMOVCC[op2 and 0xF]
        p = modrm(d, opsz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
        p = writeStr(opsBuf, p, ", ")
        p = modrm(d, opsz, reg, opsBuf, p)
      of 0x80..0x8F:
        let rel = s32(d.u32())
        mnem = JCC[op2 and 0xF]
        p = writeStr(opsBuf, p, "0x")
        p = writeHex(opsBuf, p, d.address + uint64(d.p) + uint64(rel))
      of 0x90..0x9F:
        var reg: int
        mnem = SETCC[op2 and 0xF]
        p = modrm(d, 1, reg, opsBuf, p)
      of 0xA2: mnem = "cpuid"
      of 0xAF:
        var reg: int
        mnem = "imul"
        p = modrm(d, opsz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
        p = writeStr(opsBuf, p, ", ")
        p = modrm(d, opsz, reg, opsBuf, p)
      of 0xB6, 0xB7:
        var reg: int
        let sz = if op2 == 0xB6: 1 else: 2
        mnem = "movzx"
        p = modrm(d, sz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
        p = writeStr(opsBuf, p, ", ")
        p = modrm(d, sz, reg, opsBuf, p)
      of 0xBE, 0xBF:
        var reg: int
        let sz = if op2 == 0xBE: 1 else: 2
        mnem = "movsx"
        p = modrm(d, sz, reg, opsBuf, p)
        p = writeStr(opsBuf, p, regName(opsz, reg, d.hasRex))
        p = writeStr(opsBuf, p, ", ")
        p = modrm(d, sz, reg, opsBuf, p)
      else: discard
    else: discard

  # epilogue: prefix + mnem + " " + operands -> outBuf
  var q = 0
  if d.lock: q = writeStr(outBuf, q, "lock ")
  if d.rep == 0xF3: q = writeStr(outBuf, q, "rep ")
  elif d.rep == 0xF2: q = writeStr(outBuf, q, "repne ")
  q = writeStr(outBuf, q, mnem)
  if p > 0:
    q = writeChar(outBuf, q, ' ')
    opsBuf[p] = '\0'
    q = writeStr(outBuf, q, cast[cstring](addr opsBuf[0]))
  outBuf[q] = '\0'
  result = d.p


