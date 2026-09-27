from kstd/option import hasPtrNiche, Option
import drivers/output/vga
import arch/arch_specific

type
  InterruptFrame* = object
    r15*, r14*, r13*, r12*, r11*, r10*, r9*, r8*: uint64
    rdi*, rsi*, rbp*, rbx*, rdx*, rcx*, rax*:     uint64
    vector*, error*:                              uint64
    rip*, cs*, rflags*:                           uint64
    rsp*, ss*:                                    uint64 

  FaultHandler* = proc(frame: ptr InterruptFrame): cint {.cdecl.}

static:
  doAssert sizeof(InterruptFrame) == 22 * 8, "Assertion failed: expected InterruptFrame size to be 22 * 8 bytes"
  doAssert hasPtrNiche(FaultHandler), "FaultHandler lost its niche"
  doAssert sizeof(Option[FaultHandler]) == sizeof(pointer)



proc putReg(name: cstring, v: uint64) {.inline.} =
  put "  "
  put name
  put "="
  putHex v
  put ','

proc putFlag(name: cstring, set: bool) {.inline.} =
  put name
  put ": "
  put (if set: '1' else: '0')

# ---- main ----

proc dumpRegs*(f: InterruptFrame) {.x86_64.} =
  ## Dump every field of an interrupt frame, plus decoded RFLAGS.
  # general-purpose registers
  putReg "rax", f.rax
  putReg "rbx", f.rbx
  putReg "rcx", f.rcx
  putReg "rdx", f.rdx
  putReg "rsi", f.rsi
  putReg "rdi", f.rdi
  putReg "rbp", f.rbp
  putReg "rsp", f.rsp
  putReg "r8",  f.r8
  putReg "r9",  f.r9
  putReg "r10", f.r10
  putReg "r11", f.r11
  putReg "r12", f.r12
  putReg "r13", f.r13
  putReg "r14", f.r14
  putReg "r15", f.r15

  # interrupt frame metadata
  putReg "rip", f.rip
  putReg "cs",  f.cs
  putReg "ss",  f.ss

  # decoded RFLAGS
  put "  rflags="
  putHex f.rflags
  put " {"

  putFlag "cf",  (f.rflags and (1'u64 shl 0))  != 0
  put ", "
  putFlag "pf",  (f.rflags and (1'u64 shl 2))  != 0
  put ", "
  putFlag "af",  (f.rflags and (1'u64 shl 4))  != 0
  put ", "
  putFlag "zf",  (f.rflags and (1'u64 shl 6))  != 0
  put ", "
  putFlag "sf",  (f.rflags and (1'u64 shl 7))  != 0
  put ", "
  putFlag "tf",  (f.rflags and (1'u64 shl 8))  != 0
  put ", "
  putFlag "if",  (f.rflags and (1'u64 shl 9))  != 0
  put ", "
  putFlag "df",  (f.rflags and (1'u64 shl 10)) != 0
  put ", "
  putFlag "of",  (f.rflags and (1'u64 shl 11)) != 0
  put ", "
  put "iopl: "
  put ((f.rflags shr 12) and 0x3'u64)
  put ", "
  putFlag "nt",  (f.rflags and (1'u64 shl 14)) != 0
  put ", "
  putFlag "rf",  (f.rflags and (1'u64 shl 16)) != 0
  put ", "
  putFlag "vm",  (f.rflags and (1'u64 shl 17)) != 0
  put ", "
  putFlag "ac",  (f.rflags and (1'u64 shl 18)) != 0
  put ", "
  putFlag "vif", (f.rflags and (1'u64 shl 19)) != 0
  put ", "
  putFlag "vip", (f.rflags and (1'u64 shl 20)) != 0
  put ", "
  putFlag "id",  (f.rflags and (1'u64 shl 21)) != 0
  put "}\n"
