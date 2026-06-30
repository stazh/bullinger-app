xquery version "3.1";

(:~
 : This is the place to import your own XQuery modules for either:
 :
 : 1. custom API request handling functions
 : 2. custom templating functions to be called from one of the HTML templates
 :)
module namespace api="http://teipublisher.com/api/custom";

declare namespace tei="http://www.tei-c.org/ns/1.0";

(: Add your own module imports here :)
import module namespace app="teipublisher.com/app" at "app.xql";
import module namespace cr="jinntec.de/cleanup-register-data" at "util/cleanup-register-data.xqm";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace facets="http://teipublisher.com/facets" at "facets.xql";

import module namespace roaster="http://e-editiones.org/roaster";

import module namespace ext="http://teipublisher.com/ext-common" at "ext.xql";
import module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config" at "pm-config.xql";
import module namespace mapping = "http://www.bullinger-digital.ch/mapping" at "mapping.xqm";

declare variable $api:QUERY_OPTIONS := map {
    "leading-wildcard": "yes",
    "filter-rewrite": "yes"
};

(:~
 : Controls whether locality type labels (e.g. settlement, district, country)
 : are appended to locality names in the localities register.
 :)
declare variable $api:REGISTER_LOCALITIES_SHOW_TYPE_LABELS := false();

(:~
 : Keep this. This function does the actual lookup in the imported modules.
 :)
declare function api:lookup($name as xs:string, $arity as xs:integer) {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
};

declare function api:persons-all-list($request as map(*)) {
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start
    let $filter := $request?parameters?search
    let $correspondentsOnly := $request?parameters?view = "correspondents"
    
    let $entries := api:persons-all-list-filter($filter, $correspondentsOnly)
    let $sorted := api:persons-all-list-sort($entries, $sortBy, $sortDir)
    let $subset := subsequence($sorted, $start, $limit)
    return (
        session:set-attribute($config:session-prefix || ".persons.hits", $entries),
        session:set-attribute($config:session-prefix || ".persons.hitCount", count($entries)),
        map {
            "count": count($entries),
            "results":
                array {
                    for $person at $index in $subset
                        let $link := function($content) {
                            <a style="color:var(--bb-beige);text-decoration:none;" href="../persons/{$person/@xml:id}">{$content}</a>
                        }
                        return
                            map {
                                "forename": $link(ft:field($person, 'forename')[1]),
                                "surname": $link(ft:field($person, 'surname')[1]),
                                "sent-count": ft:field($person, 'sent-count')[1],
                                "received-count": ft:field($person, 'received-count')[1],
                                "mentioned-count": ft:field($person, 'mentioned-count')[1]
                            }
                }
        })
};

declare function api:persons-all-list-filter($filter as xs:string?, $correspondentsOnly as xs:boolean?) {    
    let $options := api:get-register-query-options()
    let $correspondentsFilter := if ($correspondentsOnly) then " AND (sent-count:[1 TO *] OR received-count:[1 TO *])" else ""
    let $items :=     
            if ($filter and $filter != '') 
            then (
                $config:persons//tei:person[ft:query(., '(all-names:(' || $filter || '*) OR mentioned-names:(' || $filter || '*))' || $correspondentsFilter, $options)]
            ) 
            else (
                $config:persons//tei:person[ft:query(., 'all-names:*' || $correspondentsFilter, $options)]
            )
    return 
        $items
};

declare function api:persons-all-list-sort($entries as element()*, $sortBy as xs:string?, $dir as xs:string?) {
    let $collation := "http://www.w3.org/2013/collation/UCA?lang=de"
    let $sorted :=
        sort($entries, $collation, function($person) {
            switch ($sortBy)
                case "name" return 
                    lower-case(ft:field($person, 'name')[1])
                case "surname" return 
                    lower-case(ft:field($person, 'surname')[1])
                case "forename" return 
                    lower-case(ft:field($person, 'forename')[1])
                case "sent-count" return
                    xs:integer(ft:field($person, 'sent-count')[1])
                case "received-count" return
                    xs:integer(ft:field($person, 'received-count')[1])
                case "mentioned-count" return
                    xs:integer(ft:field($person, 'mentioned-count')[1])
                default return
                    - (xs:integer(ft:field($person, 'sent-count')[1]) + xs:integer(ft:field($person, 'received-count')[1]))
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)
};

(:~
 : API function for listing localities, grouped by initial letter and filtered by correspondence/mention count.
 : Accepts request parameters like "search", "category", "limit", "view", "correspSent", "correspReceived".
 :)
declare function api:localities-all-list($request as map(*)) {
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $limit :=
        if ($request?parameters?limit castable as xs:integer) then
            xs:integer($request?parameters?limit)
        else
            50
    let $view :=
        let $value := normalize-space($request?parameters?view)
        return
            if ($value = ("correspondence", "mentions")) then
                $value
            else
                "all"
    let $correspSentSelected := $request?parameters?correspSent = "1"
    let $correspReceivedSelected := $request?parameters?correspReceived = "1"

    let $allCorrespPlaces := 
        ($correspSentSelected and $correspReceivedSelected) or not($correspSentSelected or $correspReceivedSelected)

    let $options := api:get-register-query-options()

    (: --- Get localities mapping --- :)
    let $mapping := mapping:get-localities()

    (: --- Construct Lucene query based on view mode and search term --- :)
    let $baseQuery :=
        if ($view = "correspondence") then 
            "name:*"
        else if ($view = "mentions") then 
            "mentioned-names:*"
        else 
            "name:* OR mentioned-names:*"

    let $query :=
        if ($search != "") then
            if ($view = "correspondence") then
                "name:(" || $search || "*)"
            else if ($view = "mentions") then
                "mentioned-names:(" || $search || "*)"
            else
                "name:(" || $search || "*) OR mentioned-names:(" || $search || "*)"
        else
            $baseQuery 

    (: --- Perform fulltext search on localities --- :)
    let $rawPlaces := $config:localities//tei:place[
        ft:query(., $query, $options)
    ]

    (: --- Filter localities based on selected register view and correspondence role --- :)
    let $places := 
        for $place in $rawPlaces
        let $id := $place/@xml:id/string()
        let $placeCounts := $mapping($id)
        where exists($placeCounts)
        and (
            if ($view = "correspondence") then
                if ($allCorrespPlaces) then
                    $placeCounts?corresp > 0
                else if ($correspSentSelected) then
                    $placeCounts?correspSent > 0
                else
                    $placeCounts?correspReceived > 0
            else if ($view = "mentions") then
                $placeCounts?mentions > 0
            else
                $placeCounts?correspAndMentions > 0
        )
        return $place

    (: --- Group results by first uppercase letter of name field --- :)
    let $byLetter :=
        map:merge(
            for $place in $places
            let $name := ft:field($place, 'name')[1]
            order by lower-case($name)
            group by $letter := upper-case(substring($name, 1, 1))
            return
                map:entry($letter, $place)
        )

    (: --- Determine selected letter category --- :)
    let $letter :=
        if ((count($places) < $limit) or $search != '') then
            "[A-Z]"
        else if (not($letterParam) or $letterParam = '') then
            head(sort(map:keys($byLetter)))
        else
            $letterParam

    (: --- Select items to return based on selected letter category --- :)
    let $itemsToShow :=
        if ($letter = '[A-Z]') then
            $places
        else
            $byLetter($letter)

    (: --- Build and return the final response map --- :)
    return
        map {
            "items": api:output-locality($itemsToShow, $letter, $search, $mapping),
            "categories":
                if ((count($places) < $limit)  or $search != '') then
                    []
                else array {
                    for $index in 1 to string-length('0123456789AÄBCDEFGHIJKLMNOÖPQRSTUÜVWXYZ')
                    let $alpha := substring('0123456789AÄBCDEFGHIJKLMNOÖPQRSTUÜVWXYZ', $index, 1)
                    let $hits := count($byLetter($alpha))
                    where $hits > 0
                    return
                        map {
                            "category": $alpha,
                            "count": $hits
                        },
                    map {
                        "category": "[A-Z]",
                        "count": count($places),
                        "label": <pb-i18n key="registers.all">Alle</pb-i18n>
                    }
                }
        }
};

(:~
 : Return the i18n key for the locality type represented by the given place.
 : The type is derived from the available TEI child elements, preferring
 : settlement over district and district over country.
 :)
declare function local:locality-type-key($place as element(tei:place)) as xs:string? {
    if ($place/tei:settlement) then
        "registers.localityType.settlement"
    else if ($place/tei:district) then
        "registers.localityType.district"
    else if ($place/tei:country) then
        "registers.localityType.country"
    else
        ()
};

(:~
 : Determine whether the locality name should be disambiguated with a type label.
 : A label is added for duplicate names and for broader geographic entities
 : such as districts or countries which do not also define a settlement.
 :)
declare function local:locality-needs-type-label(
    $place as element(tei:place),
    $name as xs:string?,
    $duplicateNames as xs:string*
) as xs:boolean {
    ($name = $duplicateNames)
    or (exists($place/tei:district) and not($place/tei:settlement))
    or (exists($place/tei:country) and not($place/tei:settlement) and not($place/tei:district))
};

(:~
 : Build the display name for a locality in the localities register.
 : If needed, an i18n-enabled place type label is appended in square brackets
 : to distinguish places, regions, and countries.
 :)
declare function local:locality-display-name(
    $place as element(tei:place),
    $duplicateNames as xs:string*
) as node()* {
    let $name := ft:field($place, 'name')[1]
    return
        if ($api:REGISTER_LOCALITIES_SHOW_TYPE_LABELS) then
            let $typeKey := local:locality-type-key($place)
            return
                if (local:locality-needs-type-label($place, $name, $duplicateNames) and exists($typeKey)) then (
                    text { $name || " " },
                    text { "[" },
                    element span {
                        attribute class { "place-type" },
                        element pb-i18n { attribute key { $typeKey } }
                    },
                    text { "]" }
                )
                else
                    text { $name }
        else
            text { $name }
};

declare function api:output-locality($list, $letter as xs:string, $search as xs:string?, $mapping as map(*)) {
    let $count := count($list)
    let $duplicateNames :=
        if ($api:REGISTER_LOCALITIES_SHOW_TYPE_LABELS) then
            for $place in $list
            let $name := ft:field($place, 'name')[1]
            group by $name
            where count($place) > 1
            return $name
        else ()
    return
        array {
            element p {
                attribute class { "result-count" },
                <pb-i18n key="registers.resultsCount.localities">Gefundene Orte</pb-i18n>,
                text { ":" },
                element span {
                    attribute class { "result-count-output" },
                    $count
                }
            },
            element ul {
                attribute class { "place-list" },
                for $place in $list
                let $name := ft:field($place, 'name')[1]
                let $displayName := local:locality-display-name($place, $duplicateNames)
                let $id := $place/@xml:id/string()
                let $placeCounts := $mapping($id)
                let $corresp := if (exists($placeCounts?corresp)) then $placeCounts?corresp else 0
                let $correspSent := if (exists($placeCounts?correspSent)) then $placeCounts?correspSent else 0
                let $correspReceived := if (exists($placeCounts?correspReceived)) then $placeCounts?correspReceived else 0
                let $correspAndMentions := if (exists($placeCounts?correspAndMentions)) then $placeCounts?correspAndMentions else 0
                let $mentions := if (exists($placeCounts?mentions)) then $placeCounts?mentions else 0
                let $geo := normalize-space($place/tei:location/tei:geo)
                let $coords := tokenize($geo)
                order by lower-case($name) collation "http://www.w3.org/2013/collation/UCA?lang=de"
                return
                    if (string-length($name) > 0) then (
                        let $categoryParam := if ($letter = "[A-Z]") then substring($name, 1, 1) else $letter
                        let $params := "&amp;category=" || $categoryParam || "&amp;search=" || $search
                        return
                            element li {
                                attribute class { "js-place-item place-item" },

                                if (count($coords) = 2) then
                                    element pb-geolocation {
                                        attribute class { "place-geolocation" },
                                        attribute latitude { $coords[1] },
                                        attribute longitude { $coords[2] },
                                        attribute label { $name },
                                        attribute data-place-id { $id },
                                        attribute emit { "map" },
                                        attribute event { "click" },
                                        attribute zoom { 12 },

                                        element iron-icon {
                                            attribute class { "place-icon" },
                                            attribute icon { "maps:place" },
                                            attribute fill { "currentColor" }
                                        }
                                    }
                                else (
                                    element span {
                                        attribute class { "place-geolocation place-geolocation--disabled" },

                                        element iron-icon {
                                            attribute class { "no-geolocation-icon" },
                                            attribute icon { "social:public" },
                                            attribute fill { "currentColor" }
                                        }
                                    }
                                ),

                                element div {
                                    attribute class { "place-main" },

                                    element a {
                                        attribute class { "js-place-link place-link" },
                                        attribute href { $id || "?" || $params },

                                        element span {
                                            attribute class { "place-name" },
                                            $displayName
                                        }
                                    },

                                    element span {
                                        attribute class { "place-counts-tooltip" },
                                        element span {
                                            attribute class { "place-counts-label" },
                                            element pb-i18n {
                                                attribute key { "registers.correspondenceAndMentions" }
                                            }
                                        },
                                        text { ": " },
                                        element span {
                                            attribute class { "place-counts-value" },
                                            $correspAndMentions
                                        },
                                        element br {},
                                        element span {
                                            attribute class { "place-counts-label" },
                                            element pb-i18n {
                                                attribute key { "registers.correspondence" }
                                            }
                                        },
                                        text { ": " },
                                        element span {
                                            attribute class { "place-counts-value" },
                                            $corresp
                                        },

                                        if ($corresp > 0) then (
                                            element br {},
                                            element span {
                                                attribute class { "place-counts-subitem" },
                                                element span {
                                                    attribute class { "place-counts-bullet" },
                                                    text { "•" }
                                                },
                                                element span {
                                                    attribute class { "place-counts-label" },
                                                    element pb-i18n {
                                                        attribute key { "registers.correspondencePlaceOfDispatch" }
                                                    }
                                                },
                                                text { ": " },
                                                element span {
                                                    attribute class { "place-counts-value" },
                                                    $correspSent
                                                }
                                            },
                                            element br {},
                                            element span {
                                                attribute class { "place-counts-subitem" },
                                                element span {
                                                    attribute class { "place-counts-bullet" },
                                                    text { "•" }
                                                },
                                                element span {
                                                    attribute class { "place-counts-label" },
                                                    element pb-i18n {
                                                        attribute key { "registers.correspondencePlaceOfReceipt" }
                                                    }
                                                },
                                                text { ": " },
                                                element span {
                                                    attribute class { "place-counts-value" },
                                                    $correspReceived
                                                }
                                            }
                                        ) else (),

                                        element br {},
                                        element span {
                                            attribute class { "place-counts-label" },
                                            element pb-i18n {
                                                attribute key { "registers.mentions" }
                                            }
                                        },
                                        text { ": " },
                                        element span {
                                            attribute class { "place-counts-value" },
                                            $mentions
                                        }
                                    }
                                }
                            }
                    ) else ()
            }
        }
};

declare function api:sort-letters($entries as element()*, $sortBy as xs:string, $dir as xs:string) {
    let $sorted :=
        sort($entries, (), function($letter) {
            switch ($sortBy)
                case "title" return
                    lower-case(ext:get-title($letter))
                case "place" return
                    lower-case(ext:place-name(ext:place-by-letter($letter, 'sent')))
                case "recipients" return
                    lower-case(ext:correspondents-by-letter($letter, 'received'))
                case "senders" return
                    lower-case(ext:correspondents-by-letter($letter, 'sent'))
                case "recipients-place" return
                    lower-case(ext:place-name(ext:place-by-letter($letter, 'received')))
                (: Default: sort by date :)
                default return
                    let $date := $letter//tei:correspAction[@type="sent"]/tei:date
                    return if ($date/@when) then $date/@when
                    else if ($date/@notBefore) then $date/@notBefore
                    else if ($date/@notAfter) then $date/@notAfter
                    else "_" || $letter/@xml:id
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)

};

declare function api:person-filter($filter as xs:string?, $key as xs:string, $view as xs:string?) {
    let $options := api:get-register-query-options()
    let $all-letters := collection($config:data-default)//tei:TEI
    let $letters := switch ($view)
        case "correspondence" return
            $all-letters[ft:query(.//tei:text, 'correspondant:' || $key , $options)]
        default return
            $all-letters[ft:query(.//tei:text, 'mentioned-persons:' || $key , $options)]
    let $result := 
        if ($filter) then
            $letters[ft:query(.//tei:text, 'title:(' || $filter || '*)', $options)] 
        else $letters
    return 
        $result
};

declare function api:get-register-query-options() {
    map:merge((
        $api:QUERY_OPTIONS,
        map {
            "facets":
                map:merge((
                    for $param in request:get-parameter-names()[starts-with(., 'facet-')]
                    let $dimension := substring-after($param, 'facet-')
                    let $paramValue := request:get-parameter($param, ())                        
                    return
                        if($paramValue and $paramValue != "null")
                        then (
                            map {
                                $dimension: request:get-parameter($param, ())
                            }
                        ) else ()
                ))
        }
    ))
};


declare function api:register-select($request as map(*)) {
    switch($request?parameters?type)
        case "archives" return api:archives($request)
        case "organizations" return api:organizations($request)
        case "bibliography" return api:bibliography($request)
        default return ()
};

declare function api:bibliography($request as map(*)) {
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start    
    let $filter := $request?parameters?search
    
    let $log := util:log("info", "api:bibliography started")

    let $entries := api:bibliography-filter($filter)
    let $log := util:log("info", "api:bibliography entries: " || count($entries))
    let $sorted := api:bibliography-sort($entries, $sortBy, $sortDir)
    let $log := util:log("info", "api:bibliography $sorted: " || count($sorted))
    let $subset := subsequence($sorted, $start, $limit)
    return (
        (:session:set-attribute($config:session-prefix || ".bibliography.hits", $entries),
        session:set-attribute($config:session-prefix || ".bibliography.hitCount", count($entries)),:)
        map {
            "count": count($entries),
            "results":
                array {
                    for $bibl in $subset
                        let $title := ft:field($bibl, "bibl-title")
                        let $text := ft:field($bibl, "bibl-text")
                        return
                            map {
                                "title": $title,
                                "text": $text
                            }
                }
        })
};

declare function api:bibliography-filter($filter as xs:string?) {
    let $options := api:get-register-query-options()
    let $bibliography := $config:bibliography//tei:standOff/tei:listBibl
    let $result := 
        if ($filter) then
            $bibliography/tei:bibl[ft:query(., 'bibl-title:(' || $filter || '*) OR bibl-text:(' || $filter || '*)', $options)]
        else
            $bibliography/tei:bibl[ft:query(., 'bibl-title:*', $options)]
    return 
        $result
};

declare function api:bibliography-sort($entries as element()*, $sortBy as xs:string, $dir as xs:string) {
    let $sorted :=
        sort($entries, (), function($bibl) {
            switch ($sortBy)
                case "title" return
                    lower-case(ft:field($bibl, 'bibl-title')[1])
                case "text" return
                    lower-case(ft:field($bibl, 'bibl-text')[1])
                default return
                    lower-case(ft:field($bibl, 'bibl-title')[1])
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)
};

declare function api:archives($request as map(*)) {
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start    
    let $filter := $request?parameters?search
    
    let $entries := api:archives-filter($filter)
    let $log := util:log("info", "api:archives entries: " || count($entries))
    let $sorted := api:archives-sort($entries, $sortBy, $sortDir)
    let $log := util:log("info", "api:archives $sorted: " || count($sorted))
    let $subset := subsequence($sorted, $start, $limit)
    return (
        session:set-attribute($config:session-prefix || ".archives.hits", $entries),
        session:set-attribute($config:session-prefix || ".archives.hitCount", count($entries)),
        map {
            "count": count($entries),
            "results":
                array {
                    for $org in $subset
                        let $name := ft:field($org, "archive-name")
                        let $url := $org/tei:idno[@subtype="url"]/text()
                        let $count := ft:field($org, "archive-count")
                        return
                            map {
                                "archive": <a style="color:var(--bb-beige);text-decoration:none;" href="{$url}" target="_blank">{$name}</a>,
                                "document-count": <a style="color:var(--bb-beige);text-decoration:none;" href="../letters.html?facet-archive={$org/@xml:id}">{$count}</a>
                            }
                }
        })
};

declare function api:archives-filter($filter as xs:string?) {    
    let $options := api:get-register-query-options()
    let $result := 
        if ($filter) then
            $config:archives//tei:org[ft:query(., 'archive-name:(' || $filter || '*)', $options)]
        else
            $config:archives//tei:org[ft:query(., 'archive-name:*', $options)]
    return 
        $result
};

declare function api:archives-sort($entries as element()*, $sortBy as xs:string, $dir as xs:string) {
    let $sorted :=
        sort($entries, (), function($org) {
            switch ($sortBy)
                case "document-count" return 
                    xs:integer(ft:field($org, "archive-count"))
                default return
                    lower-case(ft:field($org, 'archive-name')[1])
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)
};

declare function api:organizations($request as map(*)) {
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start    
    let $filter := $request?parameters?search
    
    let $entries := api:organizations-filter($filter)
    let $sorted := api:organizations-sort($entries, $sortBy, $sortDir)
    let $subset := subsequence($sorted, $start, $limit)
    return (
        session:set-attribute($config:session-prefix || ".organizations.hits", $entries),
        session:set-attribute($config:session-prefix || ".organizations.hitCount", count($entries)),
        map {
            "count": count($entries),
            "results":
                array {
                    for $org at $index in $subset
                        let $name := ft:field($org, 'org-name')[1]
                        let $count := ft:field($org, 'org-count')[1]
                        return
                            map {
                                "name": <a style="color:var(--bb-beige);text-decoration:none;" href="../letters.html?facet-organization={$org/@xml:id}">{$name}</a>,
                                "count": $count
                            }
                }
        })
};

declare function api:organizations-filter($filter as xs:string?) {    
    let $options := api:get-register-query-options() 
    let $organizations := $config:orgs//tei:orgName[ft:query(., '*:* AND NOT org-count:0')]
    let $result := 
        if ($filter) then
            $organizations[ft:query(., 'org-name:(' || $filter || '*)', $options)]
        else
            $organizations[ft:query(., 'org-name:*', $options)]
    return 
        $result
};

declare function api:organizations-sort($entries as element()*, $sortBy as xs:string, $dir as xs:string) {
    let $sorted :=
        sort($entries, (), function($org) {
            switch ($sortBy)
                case "count" return 
                    xs:integer(ft:field($org, 'org-count')[1])
                default return
                    lower-case(ft:field($org, 'org-name')[1])
        })
    return
        if ($dir = "asc") then
            $sorted
        else
            reverse($sorted)
};

declare function api:register-person-detail($request as map(*)) {
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start    
    let $filter := $request?parameters?search

    let $entries := api:person-filter($filter,$key,$request?parameters?view)
    let $sorted := api:sort-letters($entries, $sortBy, $sortDir)
    let $subset := subsequence($sorted, $start, $limit)
    return (
        session:set-attribute($config:session-prefix || ".persons.hits", $entries),
        session:set-attribute($config:session-prefix || ".persons.hitCount", count($entries)),
        map {
            "count": count($entries),
            "results":
                array {
                    for $letter in $subset
                        let $id := $letter/@xml:id/string()
                        let $title := ext:get-title($letter)
                        let $senders := ext:correspondents-by-letter($letter, 'sent')
                        let $send-place-name := ext:place-name(ext:place-by-letter($letter, 'sent'))
                        let $date := ext:date-by-letter($letter, $request?parameters?language)
                        let $recipients := ext:correspondents-by-letter($letter, 'received')
                        let $recipients-place-name :=  ext:place-name(ext:place-by-letter($letter, 'received'))
                        return
                            map {
                                "title": <a style="color:var(--bb-beige);text-decoration:none;" href="../{$id}">{$title}</a>,
                                "senders":$senders,
                                "place": $send-place-name,
                                "date":<span>{$date}</span>,
                                "recipients":$recipients,
                                "recipients-place":$recipients-place-name
                            }
                }
        }
)};

declare function api:register-locality-detail($request as map(*)) {    
    let $key := $request?parameters?key
    let $sortBy := $request?parameters?order
    let $sortDir := $request?parameters?dir
    let $limit := $request?parameters?limit
    let $start := $request?parameters?start    
    let $filter := $request?parameters?search
    let $view := $request?parameters?view

    let $entries := api:locality-filter($filter,$key,$view)
    let $sorted := api:sort-letters($entries, $sortBy, $sortDir)
    let $subset := subsequence($sorted, $start, $limit)
    return (
        session:set-attribute($config:session-prefix || ".localities.hits", $entries),
        session:set-attribute($config:session-prefix || ".localities.hitCount", count($entries)),
        map {
            "count": count($entries),
            "results":
                array {
                    for $letter in $subset
                        let $id := $letter/@xml:id/string()
                        let $title := ext:get-title($letter)
                        let $senders := ext:correspondents-by-letter($letter, 'sent')
                        let $send-place-name := ext:place-name(ext:place-by-letter($letter, 'sent'))
                        let $date := ext:date-by-letter($letter, $request?parameters?language)
                        let $recipients := ext:correspondents-by-letter($letter, 'received')
                        let $recipients-place-name :=  ext:place-name(ext:place-by-letter($letter, 'received'))
                        return
                            map {
                                "title": <a style="color:var(--bb-beige);text-decoration:none;" href="../{$id}">{$title}</a>,
                                "senders":$senders,
                                "place": $send-place-name,
                                "date":<span>{$date}</span>,
                                "recipients":$recipients,
                                "recipients-place":$recipients-place-name
                            }
                }
        }
)};

declare function api:locality-filter($filter as xs:string?, $key as xs:string, $view as xs:string?) {    
    let $options := api:get-register-query-options()

    let $all-letters := collection($config:data-default)//tei:TEI
    let $letters := switch ($view)
        case "correspondence" return
            $all-letters[ft:query(.//tei:text, 'place:' || $key , $options)]
        case "mentions" return
            $all-letters[
                ft:query(.//tei:text, 'mentioned-places:' || $key, $options)
            ][
                .//tei:placeName[
                    @ref = $key
                    and not(ancestor::tei:correspAction)
                ]
            ]
        default return
            $all-letters[ft:query(.//tei:text, 'place:' || $key || ' OR mentioned-places:' || $key , $options)]
    let $result := 
        if ($filter) then
            $letters[ft:query(.//tei:text, 'title:(' || $filter || '*)', $options)] 
        else $letters
    return
        $result
};

declare function api:cleanup-register-data($request as map(*)) {   
    cr:cleanup-register($request?parameters?file)
};

declare function api:facets($request as map(*)) {    
    let $hits := session:get-attribute($config:session-prefix || ".hits")
    let $_ := util:log("info", "api:facets")
    where count($hits) > 0
    return
        <div>

        {
            for $config in $config:facets-persons?*
            return
                facets:display($config, $hits)
        }
        </div>

};

declare function api:facets-search($request as map(*)) {
    let $value := $request?parameters?value
    let $query := $request?parameters?query
    let $type := $request?parameters?type

    let $hits := session:get-attribute($config:session-prefix || ".hits")
    let $facets := ft:facets($hits, $type, ())

    let $facet-config := (for $f in $config:facets?*
                        where $f instance of map(*) and map:get($f, 'dimension') = $type
                        return $f)[1]
    
    let $matches := 
        for $key in if (exists($value)) 
                            then $value 
                            else map:keys($facets)
            let $text := 
                switch($type) 
                    case "sender" 
                    case "recipient"
                    case "mentioned-persons" return
                        let $persName := $config:persons/id($key)
                        return 
                            if ($persName) then
                                string-join(($persName/tei:forename/text(), $persName/tei:surname/text()), " ")
                            else $key
                    case "place"
                    case "mentioned-places"
                        return
                            let $place := $config:localities/id($key)
                            
                            let $settlement := $place//tei:settlement/text()
                            let $district := $place//tei:district/text()
                            let $country := $place//tei:country/text()
                            let $name :=  if($settlement) then ($settlement) else if ($district) then ($district) else ($country)
                            return
                                $name
                    case "archive" return
                        let $archive := $config:archives/id($key)
                        return
                            string-join(($archive/tei:orgName/text(), $archive/tei:addName/text()), ", ")
                    case "organization" return
                        let $group := $config:orgs/id($key)
                        return
                            string($group)
                    case "hbbw-number" return
                        $key
                    case "signature" return
                        $key
                    case "letter-id" return
                        $key
                    case "language-threshold" return
                        map:get($facet-config, 'output')($key)
                    case "has-facsimile" return
                        map:get($facet-config, 'output')($key)
                    case "topics" return
                        map:get($facet-config, 'output')($key)
                    default return 
                        let $_ := util:log("info", "api:facets-search: default return, $type: " || $type)
                        return 
                            ("unknown facet type " || $type)
            let $freq := $facets($key)
            (: Numerical values should be sorted by number and ascending (double negation using - and descending) :)
            order by if($type = 'hbbw-number' or $type = 'letter-id') then -(xs:integer(replace($text, "[^\d]+", ""))) else $freq descending, $text
            return 
                map {
                    "text": $text,
                    "freq": $freq,
                    "value": $key
                } 

        let $log := util:log("info", "api:facets-search: $matches: " || count($matches))
        let $filtered := filter($matches, function($item) {
            matches($item?text, '(?:^|\W)' || $request?parameters?query, 'i')
        })
        let $log := util:log("info", "api:facets-search: filtered $matches: " || count($filtered))
        return
            array { subsequence($filtered, 0, 50) }
};

declare function api:include-static-content($request as map(*)) as node()* {
    let $page := $request?parameters?page
    let $language := tokenize($request?parameters?language, '-')[1]
    let $source-document := $page || "-" || $language || ".html"
    let $path := $config:app-root || "/static/" || $source-document
    return
        if (not(doc-available($path)))
        then error((), "The content page could not be found: " || $source-document)
        else doc($path)//main/node()
};

declare function api:timeline($request as map(*)) {
    let $entries := session:get-attribute($config:session-prefix || '.hits')
    let $datedEntries := filter($entries, function($entry) {
            try {
                let $date := ft:field($entry, "date", "xs:date")
                return
                    exists($date) and year-from-date($date) != 1000
            } catch * {
                false()
            }
        })
    return
        map:merge(
            for $entry in $datedEntries
            group by $date := ft:field($entry, "date", "xs:date")
            return
                map:entry(format-date($date, "[Y0001]-[M01]-[D01]"), map {
                    "count": count($entry),
                    "info": ''
                })
        )
};

declare function api:redirect-old-url($request as map(*)) {
    let $uri := replace($request?path, "/letter/", "../file")
    return roaster:response(301,  "text/plain", "Redirected from old url", map { "Location": $uri })
};