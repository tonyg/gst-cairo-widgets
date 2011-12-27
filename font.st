PackageLoader fileInPackage: #ZLib.

Object subclass: FontDirectory [
    | allFaces |

    allFaces [
	allFaces ifNil: [allFaces := Set new].
	^ allFaces
    ]

    addFace: face [
	self allFaces add: face.
    ]

    facesMatching: familyPattern style: stylePattern [
	^ self allFaces select: [:face |
	    (familyPattern match: face familyName)
		and: [stylePattern match: face styleName]]
    ]

    faceMatching: familyPattern style: stylePattern [
	^ (self facesMatching: familyPattern style: stylePattern) anyOne
    ]
].

FontDirectory class extend [
    | instance |

    instance [
        instance ifNil: [instance := self new].
        ^ instance
    ]
].

Object subclass: FontFace [
    | familyName styleName
	ascender descender height maxAdvanceWidth maxAdvanceHeight
	underlinePosition underlineThickness
	charMap
	kerning
	glyphs
	|

    familyName [ ^familyName ]
    familyName: v [ familyName := v ]
    styleName [ ^styleName ]
    styleName: v [ styleName := v ]
    ascender [ ^ascender ]
    ascender: v [ ascender := v ]
    descender [ ^descender ]
    descender: v [ descender := v ]
    height [ ^height ]
    height: v [ height := v ]
    maxAdvanceWidth [ ^maxAdvanceWidth ]
    maxAdvanceWidth: v [ maxAdvanceWidth := v ]
    maxAdvanceHeight [ ^maxAdvanceHeight ]
    maxAdvanceHeight: v [ maxAdvanceHeight := v ]
    underlinePosition [ ^underlinePosition ]
    underlinePosition: v [ underlinePosition := v ]
    underlineThickness [ ^underlineThickness ]
    underlineThickness: v [ underlineThickness := v ]

    charMap [
	charMap ifNil: [charMap := Dictionary new].
	^ charMap
    ]

    kerning [
	kerning ifNil: [kerning := Dictionary new].
	^ kerning
    ]

    glyphs [
	glyphs ifNil: [glyphs := Dictionary new].
	^ glyphs
    ]

    glyphAt: c [
	^ glyphs at: (charMap at: c ifAbsent: [^ MissingGlyph instance])
		 ifAbsent: [^ MissingGlyph instance]
    ]
].

Object subclass: Glyph [
    | number extent horizontalBearing verticalBearing advance path |

    number [ ^ number ]
    number: v [ number := v ]
    extent [ ^ extent ]
    extent: v [ extent := v ]
    horizontalBearing [ ^ horizontalBearing ]
    horizontalBearing: v [ horizontalBearing := v ]
    verticalBearing [ ^ verticalBearing ]
    verticalBearing: v [ verticalBearing := v ]
    advance [ ^ advance ]
    advance: v [ advance := v ]
    path [ ^ path ]
    path: v [ path := v ]

    pathOn: gc [
	| i |
	i := 1.
	[ i <= path size ] whileTrue: [
	    | op |
	    op := path at: i.
	    gc perform: op withArguments: (path copyFrom: i + 1 to: i + op numArgs).
	    i := i + op numArgs + 1.
	].
    ]
].

Object subclass: MissingGlyph [
    number [ ^ nil ]
    extent [ ^ 1@1 ]
    horizontalBearing [ ^ 0@1 ]
    verticalBearing [ ^ -0.5@0 ] "Is this right??"
    advance [ ^ 1@1 ]
    path [ ^ #() ]

    pathOn: gc [
	gc moveTo: 0.1@0.1; lineTo: 0.9@0.1; lineTo: 0.9@0.9; lineTo: 0.1@0.9; closePath.
	gc moveTo: 0.2@0.2; lineTo: 0.2@0.8; lineTo: 0.8@0.8; lineTo: 0.8@0.2; closePath.
    ]
].

MissingGlyph class extend [
    | instance |

    instance [
	instance ifNil: [instance := self new].
	^ instance
    ]
].

Stream subclass: FontFaceStream [
    | stream line |

    FontFaceStream class >> on: aFileName [
	^ self new init: (ZLib.GZipInflateStream on: (FileStream open: aFileName mode: 'r'))
    ]

    FontFaceStream class >> onStream: aStream [
	^ self new init: aStream
    ]

    init: aStream [
	stream := aStream
    ]

    nextPut: notUsed [
	self shouldNotImplement
    ]

    loadLine [
	line ifNil: [line := stream nextLine].
	^ line
    ]

    dropLine [
	line := nil
    ]

    acceptableFaceHeaders [
	^ #(#familyName:
	    #styleName:
	    #ascender:
	    #descender:
	    #height:
	    #maxAdvanceWidth:
	    #maxAdvanceHeight:
	    #underlinePosition:
	    #underlineThickness:)
    ]

    unscale: val [
	^ val / 65536.0
    ]

    readFaceHeadersInto: face [
	| headerSym val spaceIndex |
	[
	    self loadLine.
	    line isEmpty ifTrue: [self dropLine. ^ self].
	    spaceIndex := line indexOf: Character space.
	    spaceIndex > 0 ifTrue: [
		headerSym := (line copyFrom: 1 to: spaceIndex - 1) asSymbol.
		(self acceptableFaceHeaders includes: headerSym)
		    ifTrue: [
			val := line copyFrom: spaceIndex + 1.
			(val first = $')
			    ifTrue: [ val := val copyFrom: 2 to: val size - 1 ]
			    ifFalse: [ val := self unscale: val asInteger ].
			face perform: headerSym with: val]].
	    self dropLine.
	] repeat
    ]

    splitByColon: aString [
	| result pos |
	"Based on CharacterArray >> substrings."
	pos := 1.
	result := OrderedCollection new.
	1 to: aString size do: [ :i |
	    ((aString at: i) = $:)
		    ifTrue: [
			result add: (aString copyFrom: pos to: i - 1).
			pos := i + 1]].
	pos <= aString size
	    ifTrue: [result add: (aString copyFrom: pos to: aString size)].
	^ result
    ]

    readCharMapInto: face [
	| pieces unicodeCh glyphIndex |
	[
	    self loadLine.
	    line isEmpty ifTrue: [self dropLine. ^ self].
	    pieces := self splitByColon: line.
	    unicodeCh := UnicodeCharacter value: pieces first asInteger.
	    glyphIndex := pieces second asInteger.
	    face charMap at: unicodeCh put: glyphIndex.
	    self dropLine.
	] repeat
    ]

    readKerningInto: face [
	| pieces key vec |
	[
	    self loadLine.
	    line isEmpty ifTrue: [self dropLine. ^ self].
	    pieces := self splitByColon: line.
	    key := pieces first asInteger -> pieces second asInteger.
	    vec := self unscale: (pieces third asInteger @ pieces fourth asInteger).
	    face kerning at: key put: vec.
	    self dropLine.
	] repeat
    ]

    nextGlyphNumberProperty [
	| v |
	v := self loadLine substrings second asInteger.
	self dropLine.
	^ self unscale: v
    ]

    nextGlyphPointProperty [
	| x y |
	x := self nextGlyphNumberProperty.
	y := self nextGlyphNumberProperty.
	^ x @ y
    ]

    compilePath: pieces [
	| path i |
	path := OrderedCollection new.
	i := 1.
	[ i <= pieces size ] whileTrue: [
	    (pieces at: i) = 'M' ifTrue: [
		path add: #moveTo:.
		path add: (self unscale: (pieces at: i+1) asInteger @ (pieces at: i+2) asInteger).
		i := i + 2.
	    ].
	    (pieces at: i) = 'L' ifTrue: [
		path add: #lineTo:.
		path add: (self unscale: (pieces at: i+1) asInteger @ (pieces at: i+2) asInteger).
		i := i + 2.
	    ].
	    (pieces at: i) = 'C' ifTrue: [
		path add: #curveTo:via:via:.
		"Note ordering to match Cairo's curveTo:via:via:
		 instead of the beginning-to-end order given in the
		 file!"
		path add: (self unscale: (pieces at: i+5) asInteger @ (pieces at: i+6) asInteger).
		path add: (self unscale: (pieces at: i+1) asInteger @ (pieces at: i+2) asInteger).
		path add: (self unscale: (pieces at: i+3) asInteger @ (pieces at: i+4) asInteger).
		i := i + 6.
	    ].
	    (pieces at: i) = 'O' ifTrue: [
		path add: #closePath.
	    ].
	    i := i + 1.
	].
	^ path asArray.
    ]

    readGlyphsInto: face [
	| glyph advanceX |
	[
	    self loadLine.
	    line ifNil: [^ self].
	    (line startsWith: 'Glyph ') ifFalse: [^ self].
	    glyph := Glyph new.
	    glyph number: line substrings second asInteger.
	    self dropLine.

	    "We use a fixed format here for simplicity, at the expense
	     of brittleness. chew.c produces glyph headers in the
	     order: width, height, horiBearingX, horiBearingY,
	     horiAdvance, vertBearingX, vertBearingY, vertAdvance."
	    glyph extent: self nextGlyphPointProperty.
	    glyph horizontalBearing: self nextGlyphPointProperty.
	    advanceX := self nextGlyphNumberProperty.
	    glyph verticalBearing: self nextGlyphPointProperty.
	    glyph advance: advanceX @ self nextGlyphNumberProperty.

	    glyph path: (self compilePath: (self loadLine substrings allButFirst)).
	    self dropLine.

	    self loadLine isEmpty ifFalse: [^ self]. "Error"
	    self dropLine.

	    face glyphs at: glyph number put: glyph.
	] repeat
    ]

    next [
	| face |
	(self loadLine startsWith: 'Face ') ifFalse: [^ nil].
	self dropLine.
	face := FontFace new.
	self readFaceHeadersInto: face.
	(self loadLine = 'Unicode') ifFalse: [^ nil].
	self dropLine.
	self readCharMapInto: face.
	(self loadLine = 'Kerning') ifFalse: [^ nil].
	self dropLine.
	self readKerningInto: face.
	self readGlyphsInto: face.
	^ face.
    ]

    close [
	stream close
    ]

    installAllOn: aDirectory [
	| face |
	[ (face := self next) isNil ] whileFalse: [ aDirectory addFace: face ].
	self close.
    ]

    installAll [
	self installAllOn: FontDirectory instance
    ]
].

Object subclass: TextRenderer [
    | pixelSize fontFace previousGlyph |

    pixelSize [ ^ pixelSize ifNil: [1] ]
    pixelSize: v [ pixelSize := v ]
    fontFace [ ^ fontFace ]
    fontFace: v [ fontFace := v ]

    kerningFor: currentGlyph [
	| key vec |
	previousGlyph ifNil: [previousGlyph := currentGlyph. ^ 0@0].
	key := previousGlyph number -> currentGlyph number.
	previousGlyph := currentGlyph.
	vec := fontFace kerning at: key ifAbsent: [^ 0@0].
	^ vec
    ]

    traceCharacter: ch on: gc [
	| glyph |
	glyph := fontFace glyphAt: ch.
	gc translateBy: (self kerningFor: glyph) * pixelSize.
	gc saveWhile: [
	    gc scaleBy: pixelSize @ pixelSize negated.
	    glyph pathOn: gc.
	].
	gc translateBy: (glyph advance x * pixelSize) @ 0.
    ]

    traceString: aString on: gc [
	previousGlyph := nil.
	aString do: [:ch | self traceCharacter: ch on: gc]
    ]
].
