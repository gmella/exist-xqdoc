xquery version "3.1";

(:~
 :)
module namespace xqdoc2openapi="http://xqdoc.org/library/xqdoc/openapi";

declare namespace xqdoc="http://www.xqdoc.org/1.0";

(:~
 :)
declare variable $xqrs2openapi:service-names := ("rest:GET", "rest:HEAD", "rest:PUT", "rest:POST", "rest:DELETE", "rest:OPTIONS", "rest:PATCH");

(:~
 :)
declare function xqdoc2openapi:param-name($literal as node())
as xs:string
{
    fn:substring(fn:substring-after(fn:substring-before(xs:string($literal), "}"), "{"), 2)
};

(:~
 :)
declare function xqdoc2openapi:get-parameter-description($function as node(), $literal as node())
as xs:string
{
  let $param-name := fn:substring-after(fn:substring-before(xs:string($literal), "}"), "{")
  return xqdoc2openapi:get-string-parameter-description($function, $param-name)
};

(:~
 :)
declare function xqdoc2openapi:get-string-parameter-description($function as node(), $param-name as xs:string)
as xs:string
{
  let $param := $function/xqdoc:comment/xqdoc:param[fn:starts-with(., $param-name)]/text()

  return
    if ($param)
    then replace(fn:substring-after($param, $param-name),'^\s+','')
    else ""
};

(:~
 :)
declare function xqdoc2openapi:schema-object($type as node())
as map(*)
{
    map:merge((
        if ($type/text() = "map:map")
        then
            map {
                "type": "array",
                "items": map {
                    "type": "file"
                }
            }
        else (
            map {
                "type": $type/text()
            },
            switch ($type/@occurrence/string())
            case "*" return map { "minItems": 0 }
            case "+" return map { "minItems": 1 }
            case "?" return map { "minItems": 0, "maxItems": 1 }
            default return map { "minItems": 1, "maxItems": 1 }
        )
    ))
};

(:~
 :)
declare function xqdoc2openapi:parameter-object($name as xs:string, $pname as xs:string, $in as xs:string, $description as xs:string?, $parameters as node()?)
as map(*)
{
    map:merge((
        map{ "name": $name },
        map{ "in": $in },
        map{ "description": $description },
        if ($parameters/xqdoc:parameter[xqdoc:name = $pname][xqdoc:type])
        then map{ "schema": xqdoc2openapi:schema-object($parameters/xqdoc:parameter[xqdoc:name = $pname]/xqdoc:type) }
        else ()
    ))
};

(:~
 :)
declare function xqdoc2openapi:service-object($function as node()?, $path as xs:string)
as map(*)?
{
  if ($function)
  then
    let $service-object := map:map()
    let $path-parameters :=
            for $token in fn:tokenize($path, "[{{}}]")[fn:starts-with(., "$")]
            return if (fn:contains($token, "=")) then fn:substring-before($token, "=") else $token

    let $responses-object := map:map()
    let $response-content-object := map:map()
    let $_ := if ($function//xqdoc:annotation[fn:starts-with(@name, "rest:produces")]) then (
        for $producer in $function//xqdoc:annotation[fn:starts-with(@name, "rest:produces")]
        return
            for $literal in $producer/xqdoc:literal
            return map:put($response-content-object, xs:string($literal), map { "schema": map { "type": "object" } }),
        map:put($responses-object, "content", $response-content-object)
    ) else ()

    let $tags-array := json:array()
    let $_ := for $tag in $function//xqdoc:custom[@tag = 'openapi-tag']
              let $tag-name := fn:normalize-space($tag/text())
              let $_push := json:array-push($tags-array, $tag-name)
              return ()

    let $request-body := map:map()
    let $request-content-object := map:map()
    let $_ := if ($function//xqdoc:annotation[fn:starts-with(@name, "rest:consumes")]) then (
        for $consumer in $function//xqdoc:annotation[fn:starts-with(@name, "rest:consumes")]
        return
            for $literal in $consumer/xqdoc:literal
            let $consumes-opject := map:map()
            let $schema-object := map:map()
            let $schema-put := map:put($schema-object, "type", "object")
            let $consumes-put := map:put($consumes-opject, "schema", $schema-object)
            return map:put($request-content-object, xs:string($literal), $consumes-opject),
        map:put($request-body, "content", $request-content-object)
    ) else ()

    let $parameters-array := json:array()
    let $_ := (
                for $param in $function//xqdoc:annotation[fn:starts-with(@name, "rest:form-param")]
                let $name := $param/xqdoc:literal[1]/text()
                let $pname := xqdoc2openapi:param-name($param/xqdoc:literal[2])
                let $description := xqdoc2openapi:get-parameter-description($function, $param/xqdoc:literal[2])
                let $obj := xqdoc2openapi:parameter-object($name, $pname, "formData", $description, $function//xqdoc:parameters)
                let $_push := json:array-push($parameters-array, $obj)
                return (),
                for $param in $function//xqdoc:annotation[fn:starts-with(@name, "rest:query-param")]
                let $name := $param/xqdoc:literal[1]/text()
                let $pname := xqdoc2openapi:param-name($param/xqdoc:literal[2])
                let $description := xqdoc2openapi:get-parameter-description($function, $param/xqdoc:literal[2])
                let $obj := xqdoc2openapi:parameter-object($name, $pname, "query", $description, $function//xqdoc:parameters)
                let $_push := json:array-push($parameters-array, $obj)
                return (),
                for $param in $function//xqdoc:annotation[fn:starts-with(@name, "rest:header-param")]
                let $name := $param/xqdoc:literal[1]/text()
                let $pname := xqdoc2openapi:param-name($param/xqdoc:literal[2])
                let $description := xqdoc2openapi:get-parameter-description($function, $param/xqdoc:literal[2])
                let $obj := xqdoc2openapi:parameter-object($name, $pname, "header", $description, $function//xqdoc:parameters)
                let $_push := json:array-push($parameters-array, $obj)
                return (),
                for $param in $function//xqdoc:annotation[fn:starts-with(@name, "rest:cookie-param")]
                let $name := $param/xqdoc:literal[1]/text()
                let $pname := xqdoc2openapi:param-name($param/xqdoc:literal[2])
                let $description := xqdoc2openapi:get-parameter-description($function, $param/xqdoc:literal[2])
                let $obj := xqdoc2openapi:parameter-object($name, $pname, "cookie", $description, $function//xqdoc:parameters)
                let $_push := json:array-push($parameters-array, $obj)
                return (),
                for $param in $path-parameters
                let $name := fn:substring($param, 2)
                let $description := xqdoc2openapi:get-string-parameter-description($function, $param)
                let $obj := xqdoc2openapi:parameter-object($name, $name, "path", $description, $function//xqdoc:parameters)
                let $_push := json:array-push($parameters-array, $obj)
                return ()
    )
    let $_ := (
            map:put($service-object, "description", fn:string-join($function/xqdoc:comment/xqdoc:description/text())),
            map:put($service-object, "responses", $responses-object),
            if (json:array-size($tags-array) gt 0)
            then map:put($service-object, "tags", $tags-array)
            else (),
            if (json:array-size($parameters-array) gt 0)
            then map:put($service-object, "parameters", $parameters-array)
            else (),
            if ($function//xqdoc:annotation[@name = ("rest:PUT", "rest:POST")])
            then map:put($service-object, "requestBody", $request-body)
            else ()
    )

    return $service-object
  else ()
};

(:~
 :)
declare function xqdoc2openapi:process-xqrs-to-xqDoc-to-OpenAPI()
as map(*)
{
let $paths-object := map:map()

let $functions := fn:collection("xqdoc")/xqdoc:xqdoc/xqdoc:functions/xqdoc:function[xqdoc:annotations/xqdoc:annotation[@name = "rest:path"]]
let $path-names :=
    for $path in fn:distinct-values($functions//xqdoc:annotation[@name = "rest:path"]/xqdoc:literal[1]/text())
    order by $path
    return $path

let $paths :=
    for $path in $path-names
    let $path-functions := $functions[xqdoc:annotations/xqdoc:annotation[@name = "rest:path"][xqdoc:literal = $path]]
    let $path-object := map:map()
    let $services := (
          if (fn:not($path-functions[xqdoc:annotations/xqdoc:annotation[@name = $xqrs2openapi:service-names]]))
          then
            let $function := $path-functions[xqdoc:annotations/xqdoc:annotation[fn:not(@name = $xqrs2openapi:service-names)]][1]
            let $service-object := xqdoc2openapi:service-object($function, $path)
            return
              if (fn:exists($service-object))
              then
                if ($function//xqdoc:annotation[fn:starts-with(@name, "rest:form-param")])
                then map:put($path-object, "post", $service-object)
                else map:put($path-object, "get", $service-object)
              else ()
          else (),
          for $service-name in $xqrs2openapi:service-names
          let $function := $path-functions[xqdoc:annotations/xqdoc:annotation[@name = $service-name]][1]
          let $service-object := xqdoc2openapi:service-object($function, $path)
          return
            if (fn:exists($service-object))
            then map:put($path-object, fn:lower-case(fn:substring-after($service-name, ":")), $service-object)
            else ()
    )
    return map:put($paths-object, fn:replace($path, "\{\$", "{"), $path-object)
return $paths-object
};
