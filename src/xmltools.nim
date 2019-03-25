import xmltree,
       xmlparser,
       streams,
       strutils,
       fp/either,
       fp/list,
       fp/option,
       fp/map,
       strtabs,
       sequtils,
       re,
       sugar,
       boost/parsers

type
  Node* = distinct XmlNode
  NodeList* = List[Node]
  QNameImpl = tuple[ns: string, name: string]
  QName* = distinct QNameImpl
  Attr = (string, string)
  AttrValue* = Option[string]
  Attrs* = Map[string, string]
  Namespaces* = Map[string, string]
  NodeNotFoundError* = object of KeyError
  # We need this wrapper to generate normal error messages, and
  # module `re` doesn't have function `$` for Regex type
  XRegex* = ref object
    re: Regex
    p: string

#################################################################################################### 
# Qualified name

proc `$:`*(ns: string, name: string): QName = (ns: ns, name: name).QName

converter toQName*(name: string): QName =
  let s = name.split(":")
  if s.len == 1:
    "" $: name
  else:
    s[0] $: s[1]


proc ns*(q: QName): string = q.QNameImpl.ns
proc name*(q: QName): string = q.QNameImpl.name

proc nsDecl*(ns, url: string): Attr =
  ("xmlns" & (if ns == "": "" else: ":" & ns), url)

proc `==`*(q1, q2: QName): bool {.borrow.}

proc `$`*(qname: QName): string =
  if qname.ns == "":
    qname.name
  else:
    qname.ns & ":" & qname.name

proc fromString(q: typedesc[QName], s: string): QName =
  let lst = s.split(":")
  if lst.len >= 2:
    lst[0] $: lst[1]
  else:
    s.toQName

####################################################################################################
# Misc

proc r*(s: string): XRegex =
  new(result)
  result.re = re(s)
  result.p = s

proc `$`(r: XRegex): string = r.p

proc name*(n: Node): QName =
  if n.XmlNode.kind != xnElement:
    QName.fromString("")
  else:
    QName.fromString(n.XmlNode.tag)

proc nodeNotFoundMsg(n: string, name: string, deepSearch: bool): string =
  "Node $# doesn't have $# as it's $#" % [$n.name, name, if deepSearch: "descendant" else: "child"]

proc toMap(s: StringTableRef): Map[string,string] =
  result = newMap[string,string]()
  for k,v in s:
    result = result + (k,v)

####################################################################################################
# Node

proc `$`*(n: Node): string = n.XmlNode.`$`

proc fromStringE*(n = Node, s: string): Node =
  s.newStringStream.parseXml.Node

proc fromString*(n: typedesc[Node], s: string): EitherS[Node] =
  tryS(() => Node.fromStringE(s))

proc text*(n: Node): string = n.XmlNode.innerText

proc child*(n: Node, qname: QName): Option[Node] = n.XmlNode.child($qname).some.notNil.map((v: XmlNode) => v.Node)

proc attr*(n: Node, qname: QName): AttrValue =
  if n.XmlNode.kind == xnElement and n.XmlNode.attrsLen > 0:
    let name = $qname
    if n.XmlNode.attrs.hasKey(name): n.XmlNode.attrs[name].some.AttrValue else: string.none.AttrValue
  else:
    string.none.AttrValue

proc `/`*(n: Node, regex: XRegex): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind == xnElement:
    for ch in n.XmlNode:
      if ch.kind == xnElement and ch.tag.match(regex.re):
        result = Cons(ch.Node, result)
    result = result.reverse

proc `/`*(n: Node, qname: QName): NodeList =
  if n.XmlNode.kind != xnElement:
    result = Nil[Node]()
  elif qname.ns == "*":
    result = n / r("^(.+:)?" & qname.name & "$")
  else:
    result = Nil[Node]()
    let name = $qname
    for ch in n.XmlNode:
      if ch.kind == xnElement and ch.tag == name:
        result = Cons(ch.Node, result)
    result = result.reverse

proc `//`*(n: Node, regex: XRegex): NodeList =
  if n.XmlNode.kind != xnElement:
    result = Nil[Node]()
  else:
    result = n / regex
    for ch in n.XmlNode:
      result = result ++ ch.Node // regex

proc `//`*(n: Node, qname: QName): NodeList =
  if qname.ns == "*":
    result = n // r("^(.+:)?" & qname.name & "$")
  else:
    result = n.XmlNode.findAll($qname).asList.map((v: XmlNode) => v.Node)

proc findAttrName(n: Node, regex: XRegex): Option[QName] =
  if n.XmlNode.kind == xnElement and n.XmlNode.attrsLen > 0:
    for k in n.XmlNode.attrs.keys:
      if k.match(regex.re):
        return QName.fromString(k).some
  QName.none

proc `/@`*(n: Node, regex: XRegex): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind == xnElement:
    for ch in n.XmlNode:
      if ch.Node.findAttrName(regex).isDefined:
        result = Cons(ch.Node, result)
    result = result.reverse

proc asStrO*(n: NodeList|Node|AttrValue): Option[string]

proc `/@`*(n: Node, name: QName): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind != xnElement:
    return
  elif name.ns == "*":
    result = n /@ r("^(.+:)?" & name.name & "$")
  else:
    for ch in n.XmlNode:
      if ch.Node.attr(name).isDefined:
        result = Cons(ch.Node, result)
    result = result.reverse

proc `//@`*(n: Node, regex: XRegex): NodeList =
  if n.XmlNode.kind != xnElement:
    result = Nil[Node]()
  else:
    result = n /@ regex
    for ch in n.XmlNode:
      result = result ++ ch.Node //@ regex

proc `//@`*(n: Node, name: QName): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind != xnElement:
    return
  elif name.ns == "*":
    result = n //@ r("^(.+:)?" & name.name & "$")
  else:
    result = n /@ name
    for ch in n.XmlNode:
      result = result ++ ch.Node //@ name

proc namespaces*(n:Node): Namespaces =
  let p = n.XmlNode.attrs.toMap
  p.filter((i: (string, string)) => QName.fromString(i.key).ns == "xmlns")
  .map((i: (string, string)) => (i.value, QName.fromString(i.key).name))

####################################################################################################
# NodeList

proc `$`*(lst: NodeList): string =
  lst.foldLeft("", (s: string, n: Node) => s & $n)

proc `/`*(lst: NodeList, qname: QName): NodeList =
  lst.flatMap((n: Node) => n / qname)

proc `//`*(lst: NodeList, qname: QName): NodeList =
  lst.flatMap((n: Node) => n // qname)

proc text*(lst: NodeList): string =
  lst.foldLeft("", (s: string, n: Node) => s & n.text)

#################################################################################################### 
# Data getters

proc `/!`*(n: NodeList|Node, v: QName|XRegex): Node =
  let res = n / v
  if res.isEmpty:
    when n is Node:
      raise newException(NodeNotFoundError, nodeNotFoundMsg($n.name, $v, false))
    else:
      raise newException(NodeNotFoundError, nodeNotFoundMsg("<NodeList>", $v, false))
  res.head

proc `//!`*(n: NodeList|Node, v: QName|XRegex): Node =
  let res = n // v
  if res.isEmpty:
    when n is Node:
      raise newException(NodeNotFoundError, nodeNotFoundMsg($n.name, $v, true))
    else:
      raise newException(NodeNotFoundError, nodeNotFoundMsg("<NodeList>", $v, true))
  res.head

proc asStrO(n: NodeList|Node|AttrValue): Option[string] =
  when n is NodeList:
    n.headOption.map((n: Node) => n.text).notEmpty
  elif n is AttrValue:
    n
  else:
    n.text.some.notEmpty

proc asStr*(n: NodeList|Node|AttrValue): string =
  n.asStrO.getOrElse("")

proc asIntO*(n: NodeList|Node|AttrValue): Option[int] =
  n.asStrO.map((v: string) => v.strToInt)

proc asInt*(n: Node|AttrValue): int =
  n.asStr.strToInt

proc asInt64O*(n: NodeList|Node|AttrValue): Option[int64] =
  n.asStrO.map((v: string) => v.strToInt64)

proc asInt64*(n: Node|AttrValue): int64 =
  n.asStr.strToInt64

proc asUIntO*(n: NodeList|Node|AttrValue): Option[uint] =
  n.asStrO.map((v: string) => v.strToUInt)

proc asUInt*(n: Node|AttrValue): uint =
  n.asStr.strToUInt

proc asUInt64O*(n: NodeList|Node|AttrValue): Option[uint64] =
  n.asStrO.map((v: string) => v.strToUInt64)

proc asUInt64*(n: Node|AttrValue): uint64 =
  n.asStr.strToUInt64

#####################################################################################################
# XmlBuilder

type NodeBuilder* = () -> Node

proc run*(b: NodeBuilder): Node = b()

proc endn*(): List[NodeBuilder] = Nil[NodeBuilder]()

proc attrs*(attrs: varargs[Attr]): Attrs =
  asMap(attrs)

proc el*(qname: Qname, attrs: Attrs, children: List[NodeBuilder]): NodeBuilder =
  result = proc(): Node =
    var res = ($qname).newElement
    res.attrs = newStringTable()
    attrs.forEach((v: Attr) => (res.attrs[v.key] = v.value))
    children.forEach((nb: NodeBuilder) => res.add(nb().XmlNode))
    result = res.Node
proc el*(qname: Qname, attrs: Attrs, children: varargs[NodeBuilder]): NodeBuilder = el(qname, attrs, asList(children))
proc el*(qname: Qname, children: List[NodeBuilder]): NodeBuilder = el(qname, attrs(), children)
proc el*(qname: Qname, children: varargs[NodeBuilder]): NodeBuilder = el(qname, attrs(), asList(children))

proc textEl*(data: string): NodeBuilder =
  () => newText(data).Node
