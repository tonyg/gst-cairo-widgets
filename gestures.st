"TODO: Hysteresis. The touchscreen on the neo can be very noisy."

Object subclass: Hand [
    | name
	dragSensitivity
	position
	hoverWidget initialWidget activeMode
	downButtons draggingButtons downPositions |

    Hand class >> new [
	^ super new initialize
    ]

    initialize [
	dragSensitivity := 2.
	downButtons := Set new.
	draggingButtons := Set new.
	downPositions := Dictionary new.
    ]

    name [ ^name ]
    name: aName [ name := aName ]
    dragSensitivity [ ^dragSensitivity ]
    dragSensitivity: aNumber [ dragSensitivity := aNumber ]
    position [ ^position ]
    position: aPoint [ position := aPoint ]
    initialWidget [ ^initialWidget ]
    initialWidget: aWidget [ initialWidget := aWidget ]
    activeMode [ ^activeMode ]

    activeMode: aMode [
	activeMode ifNotNil: [ :m | m hand: nil ].
	aMode ifNotNil: [ :m | m hand: self ].
	activeMode := aMode.
    ]

    hoverOver: currentHover [
	hoverWidget == currentHover ifFalse: [
	    hoverWidget ifNotNil: [ :hw | hw lostCursor ].
	    hoverWidget := currentHover.
	    hoverWidget ifNotNil: [ :hw | hw gainedCursor ]].
    ]

    currentTarget [
	^ (activeMode == nil)
	    ifFalse: [ activeMode ]
	    ifTrue: [
		(initialWidget == nil)
		    ifFalse: [ initialWidget ]
		    ifTrue: [ nil ]]
    ]

    handleMouseMotion: p [
	self currentTarget ifNotNil: [ :aw | | localP |
	    localP := aw deviceToLocalTransform transformPoint: p.
	    downButtons do: [ :button |
		(draggingButtons includes: button) ifFalse: [
		    (self checkDrag: button at: p) ifTrue: [
			aw dragStarted: button at: localP over: hoverWidget.
			draggingButtons add: button]]].
	    aw mouseMovedTo: localP over: hoverWidget].
    ]

    checkDrag: button at: p [
	| startPoint |
	startPoint := downPositions at: button ifAbsent: [ ^false ].
	^ (startPoint dist: p) > self dragSensitivity
    ]

    handleMouseButton: button state: state at: p [
	state
	    ifTrue: [
		"Button press."
		downButtons add: button.
		downPositions at: button put: p.
		draggingButtons remove: button ifAbsent: [].
		initialWidget ifNil: [ initialWidget := hoverWidget ].
		self currentTarget ifNotNil: [ :aw |
		    aw buttonPressed: button
		       at: (aw deviceToLocalTransform transformPoint: p)
		       over: hoverWidget ]]
	    ifFalse: [
		"Button release."
		downButtons remove: button.
		self currentTarget ifNotNil: [ :aw |
		    | localP |
		    localP := aw deviceToLocalTransform transformPoint: p.
		    (draggingButtons includes: button)
			ifTrue: [ aw dragReleased: button at: localP over: hoverWidget ]
			ifFalse: [ aw clicked: button at: localP ].
		    aw buttonReleased: button at: localP over: hoverWidget.
		    downButtons isEmpty ifTrue: [
			aw allButtonsReleasedAt: localP over: hoverWidget.
			initialWidget := nil]]].
    ]
].

SDL.SdlEventHandler subclass: GestureRecogniser [
    | target
	hands
	activeHand
	keyWidget |

    GestureRecogniser class >> new [
	^ super new initialize
    ]

    initialize [
	hands := Dictionary new.
    ]

    target [ ^target ]
    target: aTarget [ target := aTarget ]
    activeHand [ ^activeHand ]
    keyWidget [ ^keyWidget ]

    hover: which over: p [
	| w |
	activeHand := hands at: which ifAbsentPut: [ Hand new name: which ].
	w := target widgetUnderHand: activeHand at: p.
	activeHand position: p.
	activeHand hoverOver: w.
	keyWidget == w ifFalse: [
	    w handlesKeys ifTrue: [
		keyWidget := w]] "gives mediated follow-focus."
    ]

    handleMouseMotion: which state: state at: p rel: rel [
	self hover: which over: p.
	activeHand handleMouseMotion: p.
    ]

    handleMouseButton: which button: button state: state at: p [
	self hover: which over: p.
	activeHand handleMouseButton: button state: state at: p.
    ]

    handleKey: which state: pressed scanCode: code sym: sym mod: modifierSet unicode: unicodeCh [
	keyWidget ifNil: [^self].
	pressed
	    ifTrue: [keyWidget keyPressed: sym unicode: unicodeCh modifiers: modifierSet]
	    ifFalse: [keyWidget keyReleased: sym unicode: unicodeCh modifiers: modifierSet].
    ]

    handleWMQuitRequest [
	target handleWMQuitRequest.
    ]
].
