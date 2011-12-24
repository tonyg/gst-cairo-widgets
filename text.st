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

Object subclass: SpanLine [
    | spans positionCount width baselineOffset leading height topLine positionOffset |

    topLine [ ^topLine ]
    positionOffset [ ^positionOffset ]
    topLine: topLineNumber positionOffset: positionOffsetNumber [
	"Private. Set various accumulated positions for this object."
	topLine := topLineNumber.
	positionOffset := positionOffsetNumber.
    ]

    addSpan: aSpan [
	spans ifNil: [
	    spans := OrderedCollection new.
	    positionCount := 0.
	    width := 0.
	    baselineOffset := 0.
	    leading := 0.
	    height := 0].
	spans add: aSpan.
	positionCount := positionCount + aSpan positionCount.
	width := width + aSpan width.
	baselineOffset := baselineOffset max: aSpan baselineOffset.
	leading := leading max: aSpan leading.
	height := height max: aSpan height.
    ]

    totalPositionCount [
	^ positionCount ifNil: [ 0 ]
    ]

    totalWidth [
	^ width ifNil: [ 0 ]
    ]

    totalHeight [
	^ spans ifNil: [ 0 ] ifNotNil: [ height + leading ]
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
	"Positions: nil for no-position, otherwise 1-based index of
	the character whose face was clicked on."
	| intraLinePosition userCoordOffset |

	spans ifNil: [^nil].
	(pointX < 0) ifTrue: [^ self leftOfLeftmostPosition].

	intraLinePosition := positionOffset.
	userCoordOffset := 0.
	spans do: [:span |
	    ((pointX >= userCoordOffset) and: [(pointX - userCoordOffset) < span width])
		ifTrue: [
		    | intraSpanPosition |
		    intraSpanPosition := span positionAtOffset: (pointX - userCoordOffset) using: gc.
		    intraSpanPosition ifNil: [self error: 'Shouldn''t be able to get nil here'].
		    ^ intraSpanPosition + intraLinePosition].
	    intraLinePosition := intraLinePosition + span positionCount.
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
	^ positionOffset + self totalPositionCount
    ]

    rectangleAtPosition: aPosition using: gc [
	| intraLinePosition userCoordOffset spanCount r |

	spans ifNil: [^nil].

	intraLinePosition := positionOffset.
	userCoordOffset := 0.
	spans do: [:span |
	    spanCount := aPosition - intraLinePosition.
	    ((aPosition >= intraLinePosition) and: [spanCount <= span positionCount])
		ifTrue: [
		    r := span rectangleAtPosition: spanCount
			      using: gc
			      top: self topLine
			      bottom: self topLine + self totalHeight.
		    r moveBy: userCoordOffset@0.
		    ^ r].
	    intraLinePosition := intraLinePosition + span positionCount.
	    userCoordOffset := userCoordOffset + span width].
	^ nil
    ]
].

Object subclass: Span [
    width [ self subclassResponsibility ]
    baselineOffset [ self subclassResponsibility ]
    leading [ self subclassResponsibility ]
    height [ self subclassResponsibility ]
    renderSpanOn: gc [ self subclassResponsibility ]
    positionCount [ self subclassResponsibility ]
    positionAtOffset: pointX [ self subclassResponsibility ]
    rectangleAtPosition: p using: gc top: top bottom: bottom [ self subclassResponsibility ]
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
	gc showText: self fragment.
    ]

    positionCount [
	^ high - low + 1
    ]

    positionAtOffset: pointX using: gc [
	| pos |
	styledText style applyTo: gc.
	pos := (styledText indexUnder: pointX low: low high: high using: gc) - low + 1.
	(pos > self positionCount)
	    ifTrue: [self error: 'Can p really be greater than positionCount?'].
	^ pos
    ]

    rectangleAtPosition: p using: gc top: top bottom: bottom [
	| s left right |
	styledText style applyTo: gc.
	s := styledText string.
	left := (gc textExtents: (s copyFrom: low to: low + p - 2)) advance x.
	right := (gc textExtents: (s copyFrom: low to: low + p - 1)) advance x.
	^ left@top corner: right@bottom
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
	^ (string indexOf: Character lf startingAt: start ifAbsent: [string size + 1]) - 1
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
	    lineStart := lineEnd + 2.
	]
    ]
].

String extend [
    asStyledText [
	^ self withStyle: nil
    ]

    withStyle: aStyle [
	^ StyledText new string: self; style: aStyle
    ]
].

Object subclass: Paragraph [
    | items |

    items [ ^ items ifNil: [ #() ] ]

    append: aStringOrText [
	items ifNil: [items := OrderedCollection new].
	items add: aStringOrText asStyledText.
    ]

    composeUsing: gc width: width [
	| lines origin positionOffset |
	gc saveWhile: [
	    gc newPath.
	    lines := OrderedCollection new.
	    lines add: SpanLine new.
	    items do: [:each |
		gc saveWhile: [each pack: lines intoWidth: width using: gc]].
	    lines last totalWidth = 0 ifTrue: [lines := lines allButLast].
	].
	origin := 0.
	positionOffset := 0.
	lines do: [:line | line topLine: origin positionOffset: positionOffset.
			   origin := origin + line totalHeight.
			   positionOffset := positionOffset + line totalPositionCount].
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
	((aPoint y - line topLine) > line totalHeight)
		ifTrue: [^ line positionOffset + line totalPositionCount].
	^ storedGC saveWhile: [ line positionAtOffset: aPoint x using: storedGC ].
    ]

    rectangleAtPosition: aPosition [
	| index line |
	lines ifNil: [^nil].
	index := (BinarySearch
		      findFirstThat: [:i |
			  line := lines at: i.
			  (aPosition <= line positionOffset)]
		      between: 1
		      and: lines size) - 1.
	(index < 1) ifTrue: [^nil].
	line := lines at: index.
	^ storedGC saveWhile: [ line rectangleAtPosition: aPosition using: storedGC ]
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
