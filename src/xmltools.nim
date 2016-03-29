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
  QName* = tuple[ns: string, name: string]
  Namespaces* = Map[string, string]

#################################################################################################### 
# Qualified name

proc `$:`*(ns: string, name: string): QName = (ns: ns, name: name)

converter toQName*(name: string): QName = "" $: name

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

proc name*(n: Node): QName =
  QName.fromString(n.XmlNode.tag)

proc text*(n: Node): string = n.XmlNode.innerText

proc child*(n: Node, qname: QName): Option[Node] = n.XmlNode.child($qname).some.notNil.map((v: XmlNode) => v.Node)

proc attr*(n: Node, qname: QName): Option[string] =
  let name = $qname
  if n.XmlNode.attrs.hasKey(name): n.XmlNode.attrs[name].some else: string.none

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
