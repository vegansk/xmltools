import unittest,
       fp/either,
       fp/option,
       fp/map,
       xmltools,
       re,
       future
import fp/list except `$`

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

  test "Namespaces":
    let xml = Node.fromStringE """
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:v2="http://acme.com/api/v2">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <v2:GetAccountListRequest>
            <v2:session_id>1</v2:session_id>
            <v2:issuer_id>2</v2:issuer_id>
        </v2:GetAccountListRequest>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""
    let nss = xml.namespaces
    require: nss.get("http://acme.com/api/v2").isDefined
    let apiNs = nss.get("http://acme.com/api/v2").get
    check: (xml // apiNs $: "session_id").text == "1"
    check: (xml // apiNs $: "issuer_id").text == "2"

  test "Advanced searches":
    let xml = Node.fromStringE """
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <SOAP-ENV:Fault>
            <faultcode>SOAP-ENV:Client</faultcode>
            <faultstring xml:lang="en">Validation error</faultstring>
            <detail>
                <description>Lily was here!</description>
                <spring-ws:ValidationError xmlns:spring-ws="http://springframework.org/spring-ws">cvc-datatype-valid.1.2.1: 'ISSUER_ID_T' is not a valid value for 'integer'.</spring-ws:ValidationError>
                <spring-ws:ValidationError xmlns:spring-ws="http://springframework.org/spring-ws">cvc-type.3.1.3: The value 'ISSUER_ID_T' of element 'v2:issuer_id' is not valid.</spring-ws:ValidationError>
            </detail>
        </SOAP-ENV:Fault>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""
    check: (xml // "*" $: "Fault").length == 1
    check: (xml // "*" $: "ValidationError").length == 2
    check: (xml // "*" $: "ValidationError").text == (xml // "*" $: "Fault" // "*" $: "ValidationError").text
    check: (xml /@ "xmlns" $: "spring-ws").length == 0
    check: (xml //@ "xmlns" $: "spring-ws").length == 2
    check: (xml /@ "*" $: "spring-ws").length == 0
    check: (xml //@ "*" $: "spring-ws").length == 2
    check: (xml /@ "xmlns:spring-ws").length == 0
    check: (xml //@ "xmlns:spring-ws").length == 2

    echo: (xml // "*:Fault")
    .flatMap((e: Node) => e // "*:description" ++ e // "*:ValidationError")
    .map((n: Node) => n.text)
    .foldLeft("", (s, v: string) => s & (if s == "": "" else: "\L") & v)

  test "Strong searches and data getters":
    let xml = Node.fromStringE """
<a>
  <b><v>test</v></b>
  <c><v>100500</v></c>
</a>
"""
    expect(NodeNotFoundError): discard xml /! "test"
    expect(NodeNotFoundError): discard xml //! "test"
    check: (xml /! r"b" /! "v").asStrO == "test".some
    check: (xml //! "v").asStrO == "test".some # Only first v is used
    check: (xml //! "v").asStr == "test" # Only first v is used
    expect(ValueError): discard (xml //! "v").asInt # Only first v is used
    check: (xml // "c" /! "v").asIntO == 100500.some
    check: (xml // "c" /! "v").asInt == 100500

  test "Parse to object":
    let xml = Node.fromStringE """
<data id="100">
  <str>Hello, world!</str>
</data>
"""
    type Data = tuple[
      id: int,
      str: string,
      optStr: Option[string]
    ]
    let o: EitherS[Data] = tryS do -> auto:
      Data((xml.attr("id").asInt, (xml /! "str").asStr, (xml / "opt_str").asStrO))
    check: o == (100, "Hello, world!", string.none).rightS

  test "XML builder":
    check: $(el"test".run) == "<test />"
    check: $(el("ns" $: "test").run) == "<ns:test />"
    let xml = el("test", el("a", el("ns" $: "child")), el("b"), el("c"))
    echo xml()
    let xmla = el("test", attrs(("a", "b")), el("a"))
    echo xmla()
    check: $(el("test", textEl("data")).run) == "<test>data</test>"
