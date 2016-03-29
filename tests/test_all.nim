import xmltools,
       unittest,
       fp.either,
       fp.option,
       future

suite "xmltools":
  test "Conversion":
    let s = "<ns:a>1234</ns:a>"
    let x = Node.fromString(s)
    require: x.isRight
    check: $(x.get) == s
    let bx = Node.fromString("<broken xml")
    require: bx.isLeft

  test "QName":
    let noNs:QName = "x"
    let withNs = "ns" $: "x"
    check: $noNs == "x"
    check: $withNs == "ns:x" 

  test "NodeList":
    let xml = Node.fromStringE """<a><b>1</b><c>1</c><b>2</b><c>2</c><b>3</b><c>3</c></a>"""
    check: $(xml / "b") == "<b>1</b><b>2</b><b>3</b>"

    let xmlWithNs = Node.fromStringE """
<ns:a>
  <ns:b>1</ns:b><ns:c>1</ns:c>
  <ns:b>2</ns:b><ns:c>2</ns:c>
  <ns:b>3</ns:b><ns:c>3</ns:c>
</ns:a>
"""
    check: $(xmlWithNs / "ns" $: "b") == "<ns:b>1</ns:b><ns:b>2</ns:b><ns:b>3</ns:b>"

    let xmlTree = Node.fromStringE """<a><b><c>1</c></b><b><c>2</c></b><b><c>3</c></b></a> """
    let ns = ""
    check: $(xmlTree / ns $: "b" / ns $: "c") == "<c>1</c><c>2</c><c>3</c>"
    check: $(xmlTree // ns $: "c") == "<c>1</c><c>2</c><c>3</c>"

  test "Accessors":
    let xml = Node.fromStringE """<a><b id="100">1</b><c>1</c><b>2</b><c>2</c><b>3</b><c>3</c></a>"""
    check: xml.name == "a"
    check: (xml // "b").text == "123"
    check: xml.child("b").flatMap((v: Node) => v.attr("id")).getOrElse("") == "100"
