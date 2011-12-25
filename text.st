Object subclass: TextStyle [
    | color family slant weight fontSize leading |

    TextStyle class >> default [
	^ self new
    ]

    color [ ^ color ifNil: [ Cairo.Color black ] ]
    color: aColor [ color := aColor ]
    family [ ^ family ifNil: [ 'sans-serif' ] ]
    family: aString [ family := aString ]
    slant [ ^ slant ifNil: [ #normal ] ]
    slant: aSymbol [ slant := aSymbol ]
    weight [ ^ weight ifNil: [ #normal ] ]
    weight: aSymbol [ weight := aSymbol ]
    fontSize [ ^ fontSize ifNil: [ 12 ] ]
    fontSize: aNumber [ fontSize := aNumber ]
    leading [ ^ leading ifNil: [ 2 ] ]
    leading: aNumber [ leading := aNumber ]

    = other [
	color = other color ifFalse: [^false].
	family = other family ifFalse: [^false].
	slant = other slant ifFalse: [^false].
	weight = other weight ifFalse: [^false].
	fontSize = other fontSize ifFalse: [^false].
	leading = other leading ifFalse: [^false].
	^true
    ]

    applyTo: gc [
	gc
	    source: self color;
	    selectFontFamily: self family slant: self slant weight: self weight;
	    fontSize: self fontSize.
    ]
].

TextStyle class extend [
    | defaultStyle |

    default [ ^ defaultStyle ifNil: [ defaultStyle := TextStyle new ] ]
    default: aStyle [ defaultStyle := aStyle ]
].

"
Positions name *boundaries* between characters.

   +---+---+---+---+---+
   | H | e | l | l | o |
   +---+---+---+---+---+
     1   2   3   4   5    = character indexes
   0   1   2   3   4   5  = positions

A position of nil indicates no position at all.

Invariants:
 - position >= 0
 - position <= text length
 - there are (text length) + 1 positions

A 'Glyph' here indicates a selectable atomic piece of text. For the
purposes of this code, things like embedded inline images count as
Glyphs.
"

Object subclass: SpanLine [
    | spans glyphCount width baselineOffset leading height topLine firstPosition |

    topLine [ ^topLine ]
    firstPosition [ ^firstPosition ]
    topLine: topLineNumber firstPosition: firstPositionNumber [
	"Private. Set various accumulated positions for this object."
	topLine := topLineNumber.
	firstPosition := firstPositionNumber.
    ]

    addSpan: aSpan [
	spans ifNil: [
	    spans := OrderedCollection new.
	    glyphCount := 0.
	    width := 0.
	    baselineOffset := 0.
	    leading := 0.
	    height := 0].
	spans add: aSpan.
	glyphCount := glyphCount + aSpan glyphCount.
	width := width + aSpan width.
	baselineOffset := baselineOffset max: aSpan baselineOffset.
	leading := leading max: aSpan leading.
	height := height max: aSpan height.
    ]

    totalGlyphCount [
	^ glyphCount ifNil: [ 0 ]
    ]

    totalWidth [
	^ width ifNil: [ 0 ]
    ]

    totalHeight [
	^ spans ifNil: [ 0 ] ifNotNil: [ height + leading ]
    ]

    lastPosition [
	^ firstPosition + self totalGlyphCount
    ]

    lastSelectablePosition [
	"TODO: treat line-ending newline differently here?"
	^ self lastPosition
    ]

    renderOn: gc [
	spans ifNil: [^self].
	gc newPath.
	gc saveWhile: [
	    gc translateBy: 0 @ baselineOffset.
	    spans do: [:each |
		each renderSpanOn: gc.
		gc translateBy: each width @ 0]].
    ]

    positionAtOffset: pointX using: gc [
	"Positions: nil for no-position, otherwise 0-based index of
	the boundary between characters closest to the click
	position."
	| intraLinePosition userCoordOffset |

	spans ifNil: [^nil].
	(pointX < 0) ifTrue: [^ self leftOfLeftmostPosition].

	intraLinePosition := firstPosition.
	userCoordOffset := 0.
	spans do: [:span |
	    ((pointX >= userCoordOffset) and: [(pointX - userCoordOffset) < span width])
		ifTrue: [
		    | intraSpanPosition |
		    intraSpanPosition :=
			span positionAtOffset: (pointX - userCoordOffset) using: gc.
		    intraSpanPosition ifNil: [self error: 'Shouldn''t be able to get nil here'].
		    ^ intraSpanPosition + intraLinePosition].
	    intraLinePosition := intraLinePosition + span glyphCount.
	    userCoordOffset := userCoordOffset + span width].
	^ self rightOfRightmostPosition
    ]

    leftOfLeftmostPosition [
	"This is a separate method to permit different policies for
	when the user clicks to the left of the leftmost character in
	a span line."
	^ nil
    ]

    rightOfRightmostPosition [
	"This is a separate method to permit different policies for
	when the user clicks to the right of the rightmost character
	in a span line."
	^ self lastSelectablePosition
    ]

    offsetAtPosition: position using: gc [
	"Returns the X coordinate of the given 0-based position."
	| intraLinePosition userCoordOffset spanCount |

	spans ifNil: [^nil].

	intraLinePosition := firstPosition.
	userCoordOffset := 0.
	spans do: [:span |
	    spanCount := position - intraLinePosition.
	    ((spanCount >= 0) and: [spanCount <= span glyphCount])
		ifTrue: [^ (span offsetAtPosition: spanCount using: gc) + userCoordOffset].
	    intraLinePosition := intraLinePosition + span glyphCount.
	    userCoordOffset := userCoordOffset + span width].
	^ nil
    ]

    rectangleBetween: lowPosition and: highPosition using: gc [
	"Returns the rectangle completely the line between the two positions."
	| top |
	top := self topLine.
	^ (self offsetAtPosition: lowPosition using: gc)@top
	    corner: (self offsetAtPosition: highPosition using: gc)@(top + self totalHeight)
    ]
].

Object subclass: Span [
    width [ self subclassResponsibility ]
    baselineOffset [ self subclassResponsibility ]
    leading [ self subclassResponsibility ]
    height [ self subclassResponsibility ]
    renderSpanOn: gc [ self subclassResponsibility ]
    glyphCount [ self subclassResponsibility ]
    positionAtOffset: pointX [ self subclassResponsibility ]
    offsetAtPosition: position using: gc [ self subclassResponsibility ]
].

Span subclass: TextSpan [
    | styledText low high extents |

    styledText: aText low: aLow high: aHigh gc: gc [
	styledText := aText.
	low := aLow.
	high := aHigh.
	extents := gc textExtents: self fragment.
    ]

    fragment [
	^ styledText string copyFrom: low to: high
    ]

    trimmedFragment [
	"Fragment, with whitespace (separators) on the right trimmed."
	| f |
	f := self fragment.
	f size to: 1 by: -1 do: [:i |
	    (f at: i) isSeparator ifFalse: [^ f copyFrom: 1 to: i]].
	^ String new
    ]

    width [
	^ extents advance x
    ]

    baselineOffset [
	^ extents bearing y negated
    ]

    leading [
	^ styledText style leading
    ]

    height [
	^ extents extent y
    ]

    renderSpanOn: gc [
	styledText style applyTo: gc.
	"gc saveWhile: [ gc moveTo: 0@0; relLineTo: 3@3; stroke ]."
	gc showText: self trimmedFragment.
    ]

    glyphCount [
	^ high - low + 1
    ]

    positionAtOffset: pointX using: gc [
	| pos |
	styledText style applyTo: gc.
	pos := (styledText positionUnder: pointX low: low high: high using: gc) - low + 1.
	(pos > self glyphCount)
	    ifTrue: [self error: 'Can p really be greater than glyphCount?'].
	^ pos
    ]

    offsetAtPosition: position using: gc [
	styledText style applyTo: gc.
	^ (gc textExtents: (styledText string copyFrom: low to: low + position - 1)) advance x
    ]
].

Object subclass: BinarySearch [
    BinarySearch class >> findFirstThat: aPredicateBlock between: lowerBound and: upperBound [
	"Searches for the earliest point between low and high
	 (inclusive) where aPredicateBlock transitions from false to
	 true. Assumes that aPredicateBlock transitions either zero
	 times or once along the stretch of integers to be
	 examined. If all the numbers tested cause aPredicateBlock to
	 return true, lowerBound is returned. If all the entries cause
	 aPredicateBlock to return false, upperBound+1 is returned."

	| low high |

	low := lowerBound - 1.
	high := upperBound + 1.

	[ (high - low) > 1 ] whileTrue: [
	    | mid |
	    mid := (low + high) // 2.
	    (aPredicateBlock value: mid)
		ifTrue: [high := mid]
		ifFalse: [low := mid]].
	^ high
    ]
].

Object subclass: StyledText [
    | string style |

    string [ ^string ]
    string: aString [ string := aString ]
    style [ ^ style ifNil: [ TextStyle default ] ]
    style: aStyle [ style := aStyle ]

    asStyledText [
	^ self
    ]

    size [ ^ string size ]

    copyFrom: a to: b [ ^ self copy string: (string copyFrom: a to: b) ]
    copyFrom: a [ ^ self copy string: (string copyFrom: a) ]

    , aString [ ^ self copy string: (string, aString) ]

    allButFirst [ ^ self copy string: (string allButFirst) ]
    allButLast [ ^ self copy string: (string allButLast) ]

    wordBreaksAfter: index upperBound: upperBound [
	^ (index = upperBound) or: [
	    (string at: index) isSeparator or: [
		(string at: index + 1) isSeparator]]
    ]

    findBreakBefore: initialPos between: lowerBound and: upperBound [
	| breakPos |
	breakPos := initialPos.
	[
	    (breakPos < lowerBound) ifTrue: [^nil].
	    (string at: breakPos) isSeparator ifTrue: [^breakPos].
	    breakPos := breakPos - 1.
	] repeat.
    ]

    indexUnder: pointX low: lowerBound high: upperBound using: gc [
	^ BinarySearch
		findFirstThat: [:i |
		    (i > upperBound) or:
			"used to compare (extent x + bearing x) against pointX"
			[(gc textExtents: (string copyFrom: lowerBound to: i)) advance x > pointX]]
		between: lowerBound
		and: upperBound
    ]

    glyphMidpoint: glyphIndex relativeTo: lowerBound using: gc [
	"Accepts glyphIndexes not only 1..(string size), but outside
	this range. Answers the left-hand or right-hand coordinates in
	that case."
	| lhs rhs |
	glyphIndex < lowerBound ifTrue: [^ 0].
	glyphIndex > string size ifTrue: [^ (gc textExtents: string) advance x].
	lhs := (gc textExtents: (string copyFrom: lowerBound to: glyphIndex - 1)) advance x.
	rhs := (gc textExtents: (string copyFrom: lowerBound to: glyphIndex)) advance x.
	^ (lhs + rhs) // 2
    ]

    positionUnder: pointX low: lowerBound high: upperBound using: gc [
	"lowerBound and upperBound are glyph indexes. Answers a
	position, though, not a glyph index; for the glyph index
	variant, see indexUnder:low:high:using:."
	^ BinarySearch
		findFirstThat: [:i |
		    "i is a position, not a glyph index."
		    (i > upperBound) or:
			[(self glyphMidpoint: i + 1 relativeTo: lowerBound using: gc) > pointX]]
		between: lowerBound - 1 "position to the left of glyph lowerBound"
		and: upperBound "position to the right of glyph upperBound"
    ]

    packWidth: width low: lowerBound high: upperBound using: gc [
	| index |
	(lowerBound > upperBound) ifTrue: [^nil].
	index := (self indexUnder: width low: lowerBound high: upperBound using: gc) - 1.
	(index < lowerBound) ifTrue: [^nil].
	(self wordBreaksAfter: index upperBound: upperBound) ifFalse: [
	    index := self findBreakBefore: index between: lowerBound and: upperBound].
	^ index
    ]

    lineEndAfter: start [
	^ string indexOf: Character lf startingAt: start ifAbsent: [^ string size]
    ]

    pack: lines intoWidth: width using: gc [
	| lineStart lineEnd |

	self style applyTo: gc.

	lineStart := 1.
	[ lineStart <= string size ] whileTrue: [
	    | low high |
 	    lineEnd := self lineEndAfter: lineStart.
	    low := lineStart.
	    [
		[ high := self packWidth: width - lines last totalWidth
			       low: low
			       high: lineEnd
			       using: gc.
		  high notNil ] whileTrue: [
		      lines last addSpan:
			  (TextSpan new styledText: self low: low high: high gc: gc).
		      low := high + 1].
		(low > lineEnd) ]
	    whileFalse: [
		(lines last totalWidth = 0)
		    ifTrue: [ lines last addSpan: (TextSpan new styledText: self
								low: low
								high: lineEnd
								gc: gc).
			      low := lineEnd + 1 ]
		    ifFalse: [ lines add: SpanLine new ]].
	    (lineEnd < string size)
		ifTrue: [ lines add: SpanLine new ].
	    lineStart := lineEnd + 1.
	]
    ]
].

CharacterArray extend [
    asStyledText [
	^ self withStyle: nil
    ]

    withStyle: aStyle [
	^ StyledText new string: self; style: aStyle
    ]
].

Object subclass: ParagraphCursor [
    "I am a zipper pointing into a paragraph."
    | itemsL itemsR itemL itemR |

    on: items item: itemIndex offset: itemPosition [
	itemsL := items copyFrom: 1 to: itemIndex - 1.
	itemsR := items copyFrom: itemIndex + 1.
	itemL := (items at: itemIndex) copyFrom: 1 to: itemPosition.
	itemR := (items at: itemIndex) string copyFrom: itemPosition + 1.
    ]

    insert: aString [
	itemL := itemL, aString.
    ]

    finishItem: aBlock [
	| i |
	i := itemL, itemR.
	i size > 0 ifTrue: [aBlock value: i]
    ]

    deleteLeft [
	itemL size > 0 ifTrue: [itemL := itemL allButLast. ^ true].
	itemsL size = 0 ifTrue: [^ false].
	self finishItem: [:i | itemsR add: i beforeIndex: 1].
	itemL := itemsL last allButLast.
	itemR := String new.
	itemsL := itemsL allButLast.
	^ true
    ]

    deleteRight [
	itemR size > 0 ifTrue: [itemR := itemR allButFirst. ^ true].
	itemsR size = 0 ifTrue: [^ false].
	self finishItem: [:i | itemsL add: i].
	itemL := StyledText new string: String new; style: itemsR first style.
	itemR := itemsR first string allButFirst.
	itemsR := itemsR allButFirst.
	^ true
    ]

    unzip [
	| items |
	items := itemsL, (Array with: (itemL, itemR)), itemsR.
	^ Paragraph new initItems: items
    ]
].

Object subclass: Paragraph [
    | items |

    items [ ^ items ifNil: [ #() ] ]

    initItems: initItems [
	items := initItems
    ]

    append: aStringOrText [
	items ifNil: [items := OrderedCollection new].
	items add: aStringOrText asStyledText.
    ]

    zipToStart [
	^ ParagraphCursor new on: items item: 1 offset: 0
    ]

    zipToEnd [
	^ ParagraphCursor new on: items item: items size offset: items last size
    ]

    zipToPosition: position [
	"TODO: Make this use BinarySearch. Perhaps keep an accumulated
	 count? Ultimately, some kind of rope-like structure would be
	 ideal."
	"Invariant: on the split between two items, prefers to index
	 into the lower-indexed item."
	| lhs rhs |
	lhs := 0.
	items doWithIndex: [:item :index |
	    rhs := lhs + item size.
	    position <= rhs ifTrue: [
		^ ParagraphCursor new on: items item: index offset: (position - lhs)].
	    lhs := rhs].
	^ self zipToEnd
    ]

    composeUsing: gc width: width [
	| lines origin firstPosition |
	gc saveWhile: [
	    gc newPath.
	    lines := OrderedCollection new.
	    lines add: SpanLine new.
	    items do: [:each |
		gc saveWhile: [each pack: lines intoWidth: width using: gc]].
	    lines last totalWidth = 0 ifTrue: [lines := lines allButLast].
	].
	origin := 0.
	firstPosition := 0.
	lines do: [:line | line topLine: origin firstPosition: firstPosition.
			   origin := origin + line totalHeight.
			   firstPosition := firstPosition + line totalGlyphCount].
	^ ParagraphComposition new initLines: lines gc: gc
    ]
].

Object subclass: ParagraphComposition [
    | lines storedGC |

    initLines: anOrderedCollection gc: aGC [
	"We store the graphics context (actually a cairo context) as a
	substitute for a separate text metrics computation
	system. Ideally, the text metrics would be completely
	independent of the particular graphics context chosen to
	render to, instead being able to be kept with a more abstract
	rasterisation of text."

	lines := anOrderedCollection.
	storedGC := aGC.  ]

    renderOn: gc [
	lines do: [:line |
	    line renderOn: gc.
	    gc translateBy: 0 @ line totalHeight].
    ]

    positionAtPoint: aPoint [
	| index line |
	lines ifNil: [^nil].
	(aPoint y < lines first topLine) ifTrue: [^nil].
	index := (BinarySearch findFirstThat: [:i | (lines at: i) topLine > aPoint y]
			       between: 1
			       and: (lines size)) - 1.
	line := lines at: index.
	((aPoint y - line topLine) > line totalHeight) ifTrue: [^ line lastSelectablePosition].
	^ storedGC saveWhile: [ line positionAtOffset: aPoint x using: storedGC ].
    ]

    minPosition [ ^ 0 ]
    maxPosition [
	lines isEmpty ifTrue: [ ^ 0 ].
	^ lines last lastSelectablePosition
    ]

    lineIndexAtPosition: position ifAbsent: aBlock [
	| index |
	index := (BinarySearch
		      findFirstThat: [:i | (lines at: i) lastPosition >= position]
		      between: 1
		      and: lines size).
	index > lines size ifTrue: [^ aBlock value].
	^ index
    ]

    lineAtPosition: position [
	^ lines at: (self lineIndexAtPosition: position ifAbsent: [^nil])
    ]

    positionBelow: position [
	| index x |
	index := self lineIndexAtPosition: position ifAbsent: [1].
	lines isEmpty ifTrue: [^ self maxPosition].
	x := (lines at: index) offsetAtPosition: position using: storedGC.
	x ifNil: [^ self maxPosition].
	index := index + 1.
	index > lines size ifTrue: [^ self maxPosition].
	^ (lines at: index) positionAtOffset: x using: storedGC
    ]

    positionAbove: position [
	| index x |
	index := self lineIndexAtPosition: position ifAbsent: [lines size].
	lines isEmpty ifTrue: [^ self minPosition].
	x := (lines at: index) offsetAtPosition: position using: storedGC.
	x ifNil: [^ self minPosition].
	index := index - 1.
	index < 1 ifTrue: [^ self minPosition].
	^ (lines at: index) positionAtOffset: x using: storedGC
    ]

    rectangleAtPosition: position [
	| line x |
	line := self lineAtPosition: position.
	line ifNil: [^nil].
	x := line offsetAtPosition: position using: storedGC.
	^ x@(line topLine) extent: 0@(line totalHeight)
    ]

    rectanglesBetween: lowPosition and: highPosition [
	"Answers a collection of rectangles covering all glyphs
	between the two given positions."
	| rs index line lhs rhs |

	rs := OrderedCollection new.
	lines ifNil: [^ rs].
	"Find the first line *past* the first line we might want to
	have a rectangle for."
	index := (BinarySearch
		      findFirstThat: [:i |
			  line := lines at: i.
			  (lowPosition < line firstPosition)]
		      between: 1
		      and: lines size) - 1.
	(index < 1) ifTrue: [
	    "If the search found the first line, then there are no
	    lines we might possibly want to examine, since we were
	    looking for the first line past the onset of the region of
	    interest."
	    ^ rs].
	[ index <= lines size and: [line := lines at: index.
				    highPosition > line firstPosition] ]
	    whileTrue: [
		lhs := lowPosition max: line firstPosition.
		rhs := highPosition min: line lastPosition.
		rs add: (storedGC saveWhile: [ line rectangleBetween: lhs
						    and: rhs
						    using: storedGC ]).
		index := index + 1].
	^ rs
    ]
].

"
Object subclass: ParagraphEditor [
    | point selection style |

    point [ ^ point ]
    point: aPositionIndex [ point := aPositionIndex ]
    selection [ ^ selection ]
    selection: anIntervalCollection [ selection := anIntervalCollection ]
    style [ ^ style ]
    style: aTextStyle [ style := aTextStyle ]

"
