xquery version "3.1";

module namespace mapping = "http://www.bullinger-digital.ch/mapping";

(:~
 : Module to load and cache locality mapping data from XML file.
 : The XML file is read once on first load, and results are stored
 : in a static variable for fast reuse.
 :)

(:~
 : Path to the XML file containing place statistics
 :)
declare variable $mapping:xml-path-localities := '/db/apps/bullinger-data/generated/localities-statistics.xml';

(:~
 : Cached locality data, loaded once at module load time.
 :)
declare variable $mapping:localities := mapping:init-localities();

(:~
 : Initialize locality data from XML file.
 :)
declare function mapping:init-localities() as map(*) {
    let $doc := doc($mapping:xml-path-localities)
    let $items := $doc//*:item
    return map:merge(
        for $item in $items
        let $placeID := $item/@xml:id/string()
        where exists($placeID)
        let $corresp := xs:integer($item/*[@type = 'corresp']/string())
        let $mentions := xs:integer($item/*[@type = 'mentions']/string())
        return map:entry($placeID, map {
            "corresp": $corresp,
            "mentions": $mentions
        })
    )
};

(:~
 : Return cached mapping.
 :)
declare function mapping:get-localities() as map(*) {
    $mapping:localities
};
