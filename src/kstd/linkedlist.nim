import kstd/option

type
  Node*[T] = object
    content: T
    next: ptr Node[T]

  List*[T] = object
    head: ptr Node[T]

proc init*[T](): List[T] {.inline.} = result.head = nil

proc isEmpty*[T](list: List[T]): bool {.inline.} =
  list.head == nil

proc push*[T](list: var List[T], node: ptr Node[T]) =
  node.next = nil
  if unlikely(list.head == nil):
    list.head = node
    return

  var tail: ptr Node[T] = list.head
  while tail.next != nil:
    tail = tail.next
  tail.next = node


proc pop*[T](list: var List[T]): Option[T] =
  # []: empty list
  if unlikely(list.head == nil):  return none(T)

  # [x]: singleton
  if unlikely(list.head.next == nil):
    result = some list.head.content
    list.head = nil
    return

  # [x, ..]: general case
  var prev: ptr Node[T] = list.head

  while prev.next.next != nil:
    prev = prev.next

  result = some prev.next.content
  prev.next = nil

proc len*[T](list: List[T]): uint {.inline.} =
  result = 0
  var curr: ptr Node[T] = list.head
  while curr != nil:
    inc result
    curr = curr.next
