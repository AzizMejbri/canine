import arch/arch_specific

proc cmov*[T](cond: bool, val1, val2: T): T {.inline, x86_64.} =
  ## Force a single `cmov` instead of a branch for scalar integer / pointer selects.
  ## Falls back to a branch for types that have no cmov form (8-bit, float, aggregates).
  when (T is SomeInteger or T is ptr or T is pointer) and sizeof(T) in {2, 4, 8}:
    result = val2
    let c = uint8(ord(cond))
    asm """
      test %[c], %[c]
      cmovne %[result], %[v1]
      : [result] "+r" (`rssult`)
      : [c] "r" (`c`), [v1] "r" (`val1`)
    """
  else:
    if cond: val1 else: val2
