import kstd/option

{.experimental: "views".}

type
  Stack*[T] = object
    capacity*, length*: uint64
    items: ptr UncheckedArray[T]

proc init*[T; N: static uint](buf: ptr array[N, T], capacity: uint64 = N): Stack[T] =
  ## capacity >= N is not checked, the user bares the responsiblity to ensure that
  result.capacity = capacity
  result.length = 0
  result.items = cast[ptr UncheckedArray[T]](ensureMove(buf))

proc isEmpty*[T](self: Stack[T]): bool = self.length == 0
proc isFull*[T](self: Stack[T]): bool = self.length == self.capacity

proc peek*[T](self: Stack[T]): lent T =
  doAssert self.length != 0, "Access to empty stck"
  self.items[self.length - 1]

proc unsafePeek*[T](self: Stack[T]): lent T =
  self.items[self.length - 1]

proc push*[T](self: var Stack[T], item: sink T) =
  doAssert self.length < self.capacity, "Stack overflow"
  wasMoved self.items[self.length]
  self.items[self.length] = ensureMove(item)
  inc self.length

proc unsafePush*[T](self: var Stack[T], item: sink T) =
  wasMoved self.items[self.length]
  self.items[self.length] = ensureMove(item)
  inc self.length

proc pop*[T](self: var Stack[T]): Option[T] =
  if self.length == 0: return none(T)
  dec self.length
  result = some ensureMove(self.items[self.length])

proc unsafePop*[T](self: var Stack[T]): T =
  dec self.length
  result = ensureMove(self.items[self.length])

proc map*[T; U](self: Stack[T], f: proc(x: T): U, outBuf: ptr UncheckedArray[T]): Stack[U] =
  result.capacity = self.capacity
  result.length = self.length
  result.items = outBuf
  for i in 0..<self.length:
    result.items[i] = f(self.items[i])


