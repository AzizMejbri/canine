## Raw debug-register access. Ring-0 only.
import macros
import arch/arch_specific

macro genRawReadDR(lo, hi: static[int]): untyped =
  result = newStmtList()
  for i in lo .. hi:
    let src =
      "proc rawReadDR" & $i & "*(): uint64 {.inline, x86_64.} =\n" &
      "  asm \"\"\"\n" &
      "    mov %%dr" & $i & ", %%rax\n" &
      "    :\"=a\"(`result`)\n" &
      "  \"\"\"\n"
    result.add parseStmt(src)

macro genRawWriteDR(lo, hi: static[int]): untyped =
  result = newStmtList()
  for i in lo .. hi:
    let src =
      "proc rawWriteDR" & $i & "*(value: uint64) {.inline, x86_64.} =\n" &
      "  asm \"\"\"\n" &
      "    mov %%rax, %%dr" & $i & "\n" &
      "    :\n" &
      "    :\"a\"(`value`)\n" &
      "  \"\"\"\n"
    result.add parseStmt(src)

# DR0..DR3 are real breakpoint address registers.
# DR6/DR7 are the status/control registers.
# DR4/DR5 don't exist on x86-64 and are deliberately omitted.
genRawReadDR(0, 3)
genRawReadDR(6, 7)
genRawWriteDR(0, 3)
genRawWriteDR(6, 7)
