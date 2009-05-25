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

    positionAtOffset: pointX [
	| intraLinePosition userCoordOffset |
	spans ifNil: [^nil].
	(pointX < 0) ifTrue: [^nil].

	intraLinePosition := 0.
	userCoordOffset := 0.
	spans do: [:span |
	    ((pointX >= userCoordOffset) and: [(pointX - userCoordOffset) < span width])
		ifTrue: [
		    | intraSpanPosition |
		    intraSpanPosition := span positionAtOffset: (pointX - userCoordOffset).
		    intraSpanPosition ifNil: [^nil].
		    ^ intraSpanPosition + intraLinePosition + positionOffset ].
	    intraLinePosition := intraLinePosition + span positionCount.
	    userCoordOffset := userCoordOffset + span width].
	^ positionOffset + positionCount + 1
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

    withTemporaryGc: aBlock [
	"Private. Invoke aBlock with a temporary graphics context that
	can be used for computing text extents in my style. This is an
	ugly kludge because of the requirement for a CairoContext in
	order to compute font metrics using Cairo."

	| gc |
	gc := World current context.
	gc saveWhile: [
	    styledText style applyTo: gc.
	    ^ aBlock value: gc].
    ]

    positionAtOffset: pointX [
	| index leftX rightX |
	self withTemporaryGc: [:gc |
	    index := styledText indexUnder: pointX low: low high: high using: gc.
	    leftX := (gc textExtents: (styledText string copyFrom: low to: index - 1)) advance x.
	    rightX := (gc textExtents: (styledText string copyFrom: low to: index)) advance x.
	    ((pointX - leftX) abs > (pointX - rightX) abs)
		ifTrue: [^ index - low + 2]
		ifFalse: [^ index - low + 1]]
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
	(lowerBound >= upperBound) ifTrue: [^nil].
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
	^ ParagraphComposition new initLines: lines
    ]
].

Object subclass: ParagraphComposition [
    | lines |

    initLines: anOrderedCollection [
	lines := anOrderedCollection.
    ]

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
	(aPoint y - line topLine) > line totalHeight ifTrue: [^nil].
	^ line positionAtOffset: aPoint x.
    ]
].
