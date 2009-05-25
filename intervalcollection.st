Object subclass: IntervalCollection [
    "I represent a collection of real-valued half-open intervals,
     [start, end), possibly including negative and positive infinity.
     Intervals are termed ""ranges"" in the code, and are represented
     as {start. end}."

    | toggles isInverted |

    IntervalCollection class >> new [
	^ super new initialize
    ]

    IntervalCollection class >> fromRanges: aCollection [
	^ self new initializeFromRanges: aCollection
    ]

    IntervalCollection class >> from: low to: high [
	| i |
	i := self new.
	(low <= high) ifTrue: [i toggles add: low. i toggles add: high + 1].
	^ i
    ]

    clippedToRange: aRange [
	^ self intersection: (self species fromRanges: {aRange})
    ]

    initialize [
	isInverted := false.
	toggles := OrderedCollection new.
    ]

    initializeFromRanges: aCollection [
	aCollection do: [:range |
	    (range first < range last)
		ifTrue: [toggles add: range first. toggles add: range last.]].
    ]

    intersection: anIntervalCollection [
	^ self pvtOp: [:a :b | a and: [b]] with: anIntervalCollection
    ]

    inverted [
	^ self copy isInverted: isInverted not
    ]

    isEmpty [
	^ isInverted not and: [toggles isEmpty]
    ]

    isInverted [
	^ isInverted
    ]

    isInverted: aBoolean [
	isInverted := aBoolean.
    ]

    postCopy [
	toggles := toggles copy.
    ]

    printOn: aStream [
	super printOn: aStream.
	isInverted
	    ifTrue: [aStream nextPutAll: '(inverted ']
	    ifFalse: [aStream nextPutAll: '('].
	toggles printOn: aStream.
	aStream nextPut: $).
    ]

    pvtOp: opBlock with: other [
	| result s1 t1 i1 l1 s2 t2 i2 l2 state oldstate time |
	s1 := isInverted.
	s2 := other isInverted.
	t1 := toggles.
	t2 := other toggles.
	i1 := 1.
	i2 := 1.
	l1 := t1 size.
	l2 := t2 size.
	state := opBlock value: s1 value: s2.
	result := self species new isInverted: state.

	[
	    (i1 > l1)
		ifTrue:
			[i2 > l2
				ifTrue: [^ result]
				ifFalse:
					[time := t2 at: i2.
					s2 := s2 not.
					i2 := i2 + 1]]
		ifFalse:
			[i2 > l2
				ifTrue:
					[time := t1 at: i1.
					s1 := s1 not.
					i1 := i1 + 1]
				ifFalse:
					[(t1 at: i1) < (t2 at: i2)
						ifTrue:
							[time := t1 at: i1.
							s1 := s1 not.
							i1 := i1 + 1]
						ifFalse:
							[(t1 at: i1) = (t2 at: i2)
								ifTrue:
									[time := t1 at: i1.
									s1 := s1 not.
									s2 := s2 not.
									i1 := i1 + 1.
									i2 := i2 + 1]
								ifFalse:
									[time := t2 at: i2.
									s2 := s2 not.
									i2 := i2 + 1]]]].
	    oldstate := state.
	    state := opBlock value: s1 value: s2.
	    oldstate = state ifFalse: [result toggles add: time].
	] repeat.
    ]

    shiftedBy: aNumber [
	| r |
	r := self species new.
	r isInverted: isInverted.
	toggles do: [:each | r toggles add: each + aNumber].
	^ r
    ]

    toggles [
	^ toggles
    ]

    union: anIntervalCollection [
	^ self pvtOp: [:a :b | a or: [b]] with: anIntervalCollection
    ]

    withoutRange: aRange [
	^ self - (self species fromRanges: {aRange})
    ]

    withRange: aRange [
	^ self union: (self species fromRanges: {aRange})
    ]

    - anIntervalCollection [
	^ self pvtOp: [:a :b | a and: [b not]] with: anIntervalCollection
    ]

    = other [
	self class == other class ifFalse: [^false].
	self isInverted = other isInverted ifFalse: [^false].
	^self toggles = other toggles
    ]
]
