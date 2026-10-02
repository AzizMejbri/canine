proc cpy*(dst, src: pointer, n: csize_t): pointer {.exportc: "memcpy", cdecl, noinline.} =
  let d = cast[ptr UncheckedArray[uint8]](dst)
  let s = cast[ptr UncheckedArray[uint8]](src)
  var i: csize_t = 0
  while i < n:
    d[i] = s[i]
    inc i
  result = dst

proc move*(dst, src: pointer, n: csize_t): pointer {.exportc: "memmove", cdecl, noinline.} =
  ## Copy n bytes, handling overlap.
  let d = cast[ptr UncheckedArray[uint8]](dst)
  let s = cast[ptr UncheckedArray[uint8]](src)
  if cast[uint](dst) < cast[uint](src):
    var i: csize_t = 0
    while i < n:
      d[i] = s[i]
      inc i
  else:
    var i = n
    while i > 0:
      dec i
      d[i] = s[i]
  result = dst

proc set*(dst: pointer, c: cint, n: csize_t): pointer {.exportc: "memset", cdecl, noinline.} =
  ## Fill n bytes at dst with byte value c (truncated to 8 bits).
  let d = cast[ptr UncheckedArray[uint8]](dst)
  let b = uint8(c and 0xFF)
  var i: csize_t = 0
  while i < n:
    d[i] = b
    inc i
  result = dst

proc cmp*(a, b: pointer, n: csize_t): cint {.exportc: "memcmp", cdecl, noinline.} =
  ## Lexicographic comparison. Returns <0, 0, or >0.
  let pa = cast[ptr UncheckedArray[uint8]](a)
  let pb = cast[ptr UncheckedArray[uint8]](b)
  var i: csize_t = 0
  while i < n:
    let x = pa[i]
    let y = pb[i]
    if x != y:
      return cint(x) - cint(y)
    inc i
  result = 0
