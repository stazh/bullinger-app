xquery version "3.1";

module namespace mapping = "http://www.bullinger-digital.ch/mapping";

(:~
 : Module to load and cache locality mapping data from CSV file.
 : The CSV file is read once on first load, and results are stored
 : in a static variable for fast reuse.
 :)

(: Path to the CSV file :)
declare variable $mapping:csv-path := '/db/apps/bullinger-data/data/mapping/localities-mapping.csv';

(:~
 : Cached locality data, loaded once at module load time.
 :)
declare variable $mapping:localities := mapping:init-localities();

(:~
 : Initialize locality data from CSV file. This runs once per module load.
 : The CSV file contains 3 columns: placeID, corresp and mentions.
 :)
declare function mapping:init-localities() as map(*) {
    let $lines := tokenize(util:binary-to-string(util:binary-doc($mapping:csv-path)), '\r?\n')
    
    return map:merge(
        for $line in subsequence($lines, 2) (: skip header :)
        let $cols := tokenize($line, ',')
        where count($cols) = 3
        let $placeID := $cols[1]
        let $corresp := xs:integer($cols[2])
        let $mentions := xs:integer($cols[3])
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
