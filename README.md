# xmltools [![nimble](https://raw.githubusercontent.com/yglukhov/nimble-tag/master/nimble.png)](https://github.com/yglukhov/nimble-tag)

[![Build Status](https://travis-ci.org/vegansk/xmltools.svg?branch=master)](https://travis-ci.org/vegansk/xmltools)

High level xml library for Nim.

## Examples ##

### Simple searches ###

```nim
let xml = Node.fromStringE """
<a>
  <b>
    <c>1</c>
  </b>
  <b>
    <c>2</c>
  </b>
  <b>
    <c>3</c>
  </b>
</a>
"""

# Find all <b> tags that's parent is <a>
let bTags = xml / "b"
# Find all <c> tags recursive starting from the root
let cTags = xml // "c"
```

### Namespaces ###

```nim
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

# Get namespaces declared in the root tag
let nss = xml.namespaces
# Check namespace presence by it's URL
if nss.get("http://acme.com/api/v2").isDefined:
  # Get the namespace by it's URL
  let apiNs = nss.get("http://acme.com/api/v2").get
  # Get the value of <v2:session_id> tag using qualified name
  let sessionId = (xml // apiNs $: "session_id").text
  # Get the value of <v2:issuer_id> tag ignoring namespaces
  let issuerId = (xml // "*:issuer_id").text
```

### Get all of the error messages in the SOAP response as multiline string ###

```nim
let xml = Node.fromStringE """
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <SOAP-ENV:Fault>
            <faultcode>SOAP-ENV:Client</faultcode>
            <faultstring xml:lang="en">Validation error</faultstring>
            <detail>
                <description>Schema validation error</description>
                <spring-ws:ValidationError xmlns:spring-ws="http://springframework.org/spring-ws">
                  cvc-datatype-valid.1.2.1: 'ISSUER_ID_T' is not a valid value for 'integer'.
                </spring-ws:ValidationError>
                <spring-ws:ValidationError xmlns:spring-ws="http://springframework.org/spring-ws">
                  cvc-type.3.1.3: The value 'ISSUER_ID_T' of element 'v2:issuer_id' is not valid.
                </spring-ws:ValidationError>
            </detail>
        </SOAP-ENV:Fault>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""

let msgs = (xml // "*:Fault")
  .flatMap((e: Node) => e // "*:description" ++ e // "*:ValidationError")
  .map((n: Node) => n.text)
  .foldLeft("", (s, v: string) => s & (if s == "": "" else: "\L") & v)
```

### Xml to object parsing ###

```nim
let xml = Node.fromStringE """
<data>
  <id>100</id>
  <str>Hello, world!</str>
</data>
"""
type Data = tuple[
  id: int,
  str: string,
  optStr: Option[string]
]
let o: EitherS[Data] = tryS do -> auto:
  ((xml /! "id").asInt, (xml /! "str").asStr, (xml / "opt_str").asStrO)
```
