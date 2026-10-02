
type
  BitArray*[N: static int] = distinct array[N div 8, uint8]

proc `[]`*[N: static int](a: BitArray[N], i: int): bool {.inline.} =
  let raw = array[N div 8, uint8](a)
  (raw[i shr 3] and (1'u8 shl (i and 7))) != 0

proc `[]=`*[N: static int](a: var BitArray[N], i: int, v: bool) {.inline.} =
  let raw = array[N div 8, uint8](a)
  let byteIdx = i shr 3
  let bitIdx = i and 7
  if v:
    raw[byteIdx] = raw[byteIdx] or (1'u8 shl bitIdx)
  else:
    raw[byteIdx] = raw[byteIdx] and not (1'u8 shl bitIdx)
  a = BitArray[N](raw)
