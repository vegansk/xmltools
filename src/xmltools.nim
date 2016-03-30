import xmltree,
       xmlparser,
       streams,
       strutils,
       fp.either,
       fp.list,
       fp.option,
       fp.map,
       strtabs,
       sequtils,
       re,
       future

type
  Node* = distinct XmlNode
  NodeList* = List[Node]
  QNameImpl = tuple[ns: string, name: string]
  QName* = distinct QNameImpl
  Attr* = MapItem[string, string]
  Attrs* = Map[string, string]
  Namespaces* = Map[string, string]

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

proc fromString(q = QName, s: string): QName =
  let lst = s.split(":")
  if lst.len >= 2:
    lst[0] $: lst[1]
  else:
    s.toQName

####################################################################################################
# Node

proc `$`*(n: Node): string = n.XmlNode.`$`

proc fromStringE*(n = Node, s: string): Node =
  s.newStringStream.parseXml.Node

proc fromString*(n = Node, s: string): EitherS[Node] =
  tryS(() => Node.fromStringE(s))

proc text*(n: Node): string = n.XmlNode.innerText

proc child*(n: Node, qname: QName): Option[Node] = n.XmlNode.child($qname).some.notNil.map((v: XmlNode) => v.Node)

proc attr*(n: Node, qname: QName): Option[string] =
  if n.XmlNode.kind == xnElement and n.XmlNode.attrsLen > 0:
    let name = $qname
    if n.XmlNode.attrs.hasKey(name): n.XmlNode.attrs[name].some else: string.none
  else:
    string.none

proc `/`*(n: Node, regex: Regex): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind == xnElement:
    for ch in n.XmlNode:
      if ch.kind == xnElement and ch.tag.match(regex):
        result = Cons(ch.Node, result)
    result = result.reverse

proc `/`*(n: Node, qname: QName): NodeList =
  if n.XmlNode.kind != xnElement:
    result = Nil[Node]()
  elif qname.ns == "*":
    result = n / re("^(.+:)?" & qname.name & "$")
  else:
    result = Nil[Node]()
    let name = $qname
    for ch in n.XmlNode:
      if ch.kind == xnElement and ch.tag == name:
        result = Cons(ch.Node, result)
    result = result.reverse

proc `//`*(n: Node, regex: Regex): NodeList =
  if n.XmlNode.kind != xnElement:
    result = Nil[Node]()
  else:
    result = n / regex
    for ch in n.XmlNode:
      result = result ++ ch.Node // regex

proc `//`*(n: Node, qname: QName): NodeList =
  if qname.ns == "*":
    result = n // re("^(.+:)?" & qname.name & "$")
  else:
    result = n.XmlNode.findAll($qname).asList.map((v: XmlNode) => v.Node)

proc findAttrName(n: Node, regex: Regex): Option[QName] =
  if n.XmlNode.kind == xnElement and n.XmlNode.attrsLen > 0:
    for k in n.XmlNode.attrs.keys:
      if k.match(regex):
        return QName.fromString(k).some
  QName.none

proc `/@`*(n: Node, regex: Regex): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind == xnElement:
    for ch in n.XmlNode:
      if ch.Node.findAttrName(regex).isDefined:
        result = Cons(ch.Node, result)
    result = result.reverse

proc `/@`*(n: Node, name: QName): NodeList =
  result = Nil[Node]()
  if n.XmlNode.kind != xnElement:
    return
  elif name.ns == "*":
    result = n /@ re("^(.+:)?" & name.name & "$")
  else:
    for ch in n.XmlNode:
      if ch.Node.attr(name).isDefined:
        result = Cons(ch.Node, result)
    result = result.reverse

proc `//@`*(n: Node, regex: Regex): NodeList =
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
    result = n //@ re("^(.+:)?" & name.name & "$")
  else:
    result = n /@ name
    for ch in n.XmlNode:
      result = result ++ ch.Node //@ name

proc name*(n: Node): QName =
  QName.fromString(n.XmlNode.tag)

proc toMap(s: StringTableRef): Map[string,string] =
  result = asMap[string,string]()
  for k,v in s:
    result = result + (k,v)

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

#####################################################################################################
# XmlBuilder

type NodeBuilder* = () -> Node

proc run*(b: NodeBuilder): Node = b()

proc endn*(): List[NodeBuilder] = Nil[NodeBuilder]()

proc el*(qname: Qname, attrs: Attrs, children: List[NodeBuilder]): NodeBuilder = 
  result = proc(): Node =
    var res = ($qname).newElement
    res.attrs = newStringTable()
    attrs.forEach((v: Attr) => (res.attrs[v.key] = v.value))
    children.forEach((nb: NodeBuilder) => res.add(nb().XmlNode))
    result = res.Node
proc el*(qname: Qname, attrs: Attrs): NodeBuilder = el(qname, attrs, endn())
proc el*(qname: Qname, attrs: Attrs, child: NodeBuilder): NodeBuilder = el(qname, attrs, child ^^ endn())
proc el*(qname: Qname, attr: Attr, children: List[NodeBuilder]): NodeBuilder = el(qname, [attr].asMap, children)
proc el*(qname: Qname, attr: Attr, child: NodeBuilder): NodeBuilder = el(qname, attr, child ^^ endn())
proc el*(qname: Qname, attr: Attr): NodeBuilder = el(qname, attr, endn())
proc el*(qname: QName, children: List[NodeBuilder]): NodeBuilder =
  el(qname, Nil[Attr]().asMap, children)
proc el*(qname: QName, child: NodeBuilder): NodeBuilder = el(qname, child ^^ endn())
proc el*(qname: QName): NodeBuilder = el(qname, endn())

proc textEl*(data: string): NodeBuilder =
  () => newText(data).Node
