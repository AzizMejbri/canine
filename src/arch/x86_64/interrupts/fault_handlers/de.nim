import arch/x86_64/interrupts/[common, faults]
import drivers/output/vga
import kstd/hooks



proc deHandler(frame: ptr InterruptFrame): cint {.cdecl.} =
  chCol White, Yellow
  put "\n=== Division Error Exception (handled by `fault_handlers::deHandler()`) ===\n"
  put "[#DE] "
  put " rip="
  putHex frame.rip
  putc '\n'
  resetCol()
  let insn = cast[ptr UncheckedArray[uint8]](frame.rip)

  # Compute length of the faulting div/idiv.
  var i = 0
  # Consume legacy prefixes and REX.
  while true:
    let b = insn[i]
    case b
    of 0x66, 0x67, 0xF0, 0xF2, 0xF3,
       0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65:
      inc i
    else:
      if (b and 0xF0) == 0x40: inc i   # REX
      else: break
  # Opcode: F6 /6|/7 (byte) or F7 /6|/7 (word/dword/qword)
  inc i
  let modrm = insn[i]; inc i
  let modVal = modrm shr 6
  let rm  = modrm and 7
  case modVal
  of 0:
    if rm == 4: inc i          # SIB
    elif rm == 5: i += 4       # disp32 (RIP-relative in 64-bit)
  of 1: inc i                  # disp8
  of 2: i += 4                 # disp32
  of 3: discard                # register operand
  else: discard

  # Publish a defined result, since the destination regs are garbage
  # after a faulting div/idiv.
  frame.rax = 0
  frame.rdx = 0

  frame.rip += uint64(i)
  0

initAppend 128:
  registerFaultHandler(deHandler, 0)
