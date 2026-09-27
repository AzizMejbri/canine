import kstd/panic


template hasPtrNiche*(T: typedesc): bool =
  when T is ptr or T is pointer:
    true
  elif (T is proc):
    sizeof(T) == sizeof(pointer)
  else:
    false

type
  OptionKind = enum None, Some
  Option*[T] = object
    when hasPtrNiche(T):
      raw: T
    else:
      value: T
      optKind: OptionKind

proc some*[T](val: T): Option[T] {.inline.} =
  when hasPtrNiche(T):
    doAssert val != nil, "some() given nil — use none()"
    Option[T](raw: val)
  else:
    Option[T](optKind: Some, value: val)

proc none*[T](): Option[T] {.inline.} =
  when hasPtrNiche(T):
    Option[T](raw: nil)
  else:
    Option[T](optKind: None)

proc none*[T](t: typedesc[T]): Option[T] {.inline.} =
  when hasPtrNiche(T):
    Option[T](raw: nil)
  else:
    Option[T](optKind: None)

proc isSome*[T](opt: Option[T]): bool {.inline.} =
  when hasPtrNiche(T):
    opt.raw != nil
  else:
    opt.optKind == Some

proc isNone*[T](opt: Option[T]): bool {.inline.} =
  when hasPtrNiche(T):
    opt.raw == nil
  else:
    opt.optKind == None

proc get*[T](opt: Option[T]): T {.inline.} =
  when hasPtrNiche(T):
    if opt.raw == nil:
      kernelAssert false, "Option.get() called on None"
    result = opt.raw
  else:
    case opt.optKind
    of Some: result = opt.value
    of None: kernelAssert false, "Option.get() called on None"

proc orElse*[T](opt: Option[T], default: T): T {.inline.} =
  when hasPtrNiche(T):
    if opt.raw == nil: default else: opt.raw
  else:
    case opt.optKind
    of Some: result = opt.value
    of None: result = default

proc map*[T, U](opt: Option[T], f: proc(x: T): U {.nimcall.}): Option[U] {.inline.} =
  when hasPtrNiche(T):
    if opt.raw == nil: return none[U]()
    let r = f opt.raw
    when hasPtrNiche(U):
      if r == nil: none(U) else: return some(r)
    else:
      return some(r)
  else:
    case opt.optKind
    of None: return none[U]()
    of Some: return some(f(opt.value))

proc `or`*[T](a, b: Option[T]): Option[T] {.inline.} =
  when hasPtrNiche(T):
    if a.raw != nil: a else: b
  else:
    case a.optKind
    of Some: a
    of None: b

proc isSomeAnd*[T](opt: Option[T], pred: proc(x: T): bool {.nimcall.}): bool {.inline.} =
  when hasPtrNiche(T):
    opt.raw != nil and pred(opt.raw)
  else:
    case opt.optKind
    of Some: pred(opt.value)
    of None: false

proc filter*[T](opt: Option[T], pred: proc(x: T): bool {.nimcall.}): Option[T] {.inline.} =
  when hasPtrNiche(T):
    if opt.raw != nil and pred(opt.raw): ensureMove(opt) else: none(T)
  else:
    case opt.optKind
    of None: ensureMove(opt)
    of Some: result = if pred(opt.value): ensureMove(opt) else: none(T)

proc `==`*[T](a, b: Option[T]): bool {.inline.} =
  when hasPtrNiche(T):
    a.raw == b.raw
  else:
    case a.optKind
    of None: b.optKind == None
    of Some:
      case b.optKind
        of Some: a.value == b.value
        of None: false
