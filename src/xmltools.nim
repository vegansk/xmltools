import xmltree,
       xmlparser,
       streams,
       strutils,
       fp.either,
       fp.list,
       future

type
  Node* = distinct XmlNode
  NodeList* = List[Node]
  QName* = tuple[ns: string, name: string]

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

proc `/`*(n: Node, qname: QName): NodeList =
  result = Nil[Node]()
  let name = $qname
  for ch in n.XmlNode:
    if ch.tag == name:
      result = Cons(ch.Node, result)
  result = result.reverse

proc `//`*(n: Node, qname: QName): NodeList =
  n.XmlNode.findAll($qname).asList.map(v => v.Node)

proc name*(n: Node): QName =
  QName.fromString(n.XmlNode.tag)

proc text*(n: Node): string = n.XmlNode.innerText

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
