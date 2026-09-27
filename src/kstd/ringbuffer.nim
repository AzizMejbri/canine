## ringbuffer.nim — lock-free SPSC overwrite ring buffer.
##
## Contract:
##   - Exactly ONE producer context (e.g. an ISR) calls `push`.
##   - Exactly ONE consumer context (e.g. the main loop) calls `pop`.
##   - `push` never fails and never blocks. If the consumer is behind,
##     the oldest unread slots are silently overwritten.
##   - The producer NEVER reads or writes `readPos`. Overflow is handled
##     entirely on the consumer side by fast-forwarding past lost items.
##
## Capacity must be a power of two.

import std/atomics
import kstd/option

type
  RingBuffer*[T; CAP: static int] = object
    data:     array[CAP, T]
    writePos: Atomic[uint64]
    readPos:  Atomic[uint64]

proc init*[T; CAP: static int](): RingBuffer[T, CAP] {.inline.} =
  static:
    doAssert CAP > 0,                    "capacity must be > 0"
    doAssert (CAP and (CAP - 1)) == 0,   "capacity must be a power of two"
  result.writePos.store(0'u64, moRelaxed)
  result.readPos.store(0'u64, moRelaxed)

proc push*[T; CAP: static int](rb: var RingBuffer[T, CAP], item: T) {.inline.} =
  const mask = uint64(CAP - 1)
  let w = rb.writePos.load moRelaxed
  rb.data[int(w and mask)] = item
  rb.writePos.store w + 1, moRelease

proc pop*[T; CAP: static int](rb: var RingBuffer[T, CAP]): Option[T] {.inline.} =
  const cap64 = uint64(CAP)
  const mask  = cap64 - 1
  let w = rb.writePos.load moAcquire
  var r = rb.readPos.load moRelaxed
  if r == w: return none(T)
  if w - r > cap64:
    r = w - cap64
  result = some rb.data[int(r and mask)]
  rb.readPos.store r + 1, moRelease

iterator drain*[T; CAP: static int](rb: var RingBuffer[T, CAP]): T =
  var slot: Option[T]
  while true:
    slot = rb.pop()
    if slot.isNone: break
    yield slot.get
