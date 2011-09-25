"TODO: (besides those in the text below)

 - Keith Packard's layout box/glue model

 - Improved label, ultimately to become a general text widget

 - test invalidation (and make it go through parents, to support a
   TWIN-style compositing architecture)

 - build a clock widget, for testing composition and animation

 - kinds of container:
   - hbox
   - vbox
   - stacked (for different Z layers?)
   - free-form
   - grid
"

FileStream fileIn: 'loadscript.st'.
FileStream fileIn: 'intervalcollection.st'.
FileStream fileIn: 'text.st'.

SDL.SdlDisplay extend [
    toggleFullscreen [
	^ (SDL.SdlVideo sdlWMToggleFullScreen: self sdlSurface) = 1
    ]
]

SDL.SdlDisplay defaultFormat extent: 800@480; fullScreen: false.
(SDL includesKey: #SdlGLDisplay)
     ifTrue: [ Smalltalk at: #Display put: SDL.SdlGLDisplay current ]
     ifFalse: [ Smalltalk at: #Display put: SDL.SdlDisplay current ].

Object subclass: Widget [
    | painter deviceToLocalTransform parent properties |

    Widget class >> new [
	^ super new initialize
    ]

    painter [ ^painter ]
    localToParentTransform [ self subclassResponsibility ]
    parentToLocalTransform [ ^ self localToParentTransform inverse ]
    parent [ ^parent ]

    deviceToLocalTransform [
	deviceToLocalTransform ifNil: [
	    deviceToLocalTransform :=
		parent ifNil: [ self parentToLocalTransform ]
		       ifNotNil: [ :p |
			   p deviceToLocalTransform after: self parentToLocalTransform ]].
	^deviceToLocalTransform
    ]

    localToDeviceTransform [ ^self deviceToLocalTransform inverse ]

    painter: aPainter [
	painter := aPainter.
    ]

    clearCachedDeviceTransform [
	deviceToLocalTransform := nil.
    ]

    parent: aContainer [
	"Private. Called by Container>>#add:."
	deviceToLocalTransform := nil.
	parent := aContainer.
    ]

    detach [
	parent ifNil: [^self].
	parent removeWidget: self.
	parent := nil.
    ]

    initialize [
    ]

    propertyAt: key [
	properties ifNil: [SystemExceptions.NotFound signalOn: key what: 'key'].
	^ properties at: key
    ]

    propertyAt: key ifAbsent: aBlock [
	properties ifNil: [^ aBlock value].
	^ properties at: key ifAbsent: aBlock
    ]

    propertyAt: key ifAbsentPut: aBlock [
	^ (properties ifNil: [ properties := Dictionary new])
	    at: key ifAbsentPut: aBlock
    ]

    propertyAt: key put: value [
	(properties ifNil: [ properties := Dictionary new ])
	    at: key put: value
    ]

    propertyAt: key put: value checkingDefault: defaultValue [
	(value = defaultValue)
            ifTrue: [ self removePropertyAt: key ]
	    ifFalse: [ self propertyAt: key put: value ]
    ]

    removePropertyAt: key [
	properties ifNil: [^self].
	properties removeKey: key ifAbsent: [].
	properties isEmpty ifTrue: [ properties := nil ].
    ]

    localBounds [
	self subclassResponsibility.
    ]

    parentBounds [
	^ self localToParentTransform transformBounds: self localBounds
    ]

    deviceBounds [
	^ self localToDeviceTransform transformBounds: self localBounds
    ]

    invalidate [
	World current invalidate: self deviceBounds.
    ]

    paintSelfOn: gc [
	painter ifNil: [ ^self ].
	painter paint: self on: gc.
    ]

    paintOn: gc [
	self localToParentTransform accept: gc.
	self paintSelfOn: gc.
    ]

    containsPoint: aPoint [
	"aPoint is in local coordinates."
	"Transcript << self << ' containsPoint: ' << aPoint << ' and localBounds ' << self localBounds; nl."
	^ self localBounds containsPoint: aPoint
    ]

    widgetUnder: aPoint [
	"aPoint is in local coordinates."
	(self containsPoint: aPoint)
	    ifTrue: [ ^self ]
	    ifFalse: [ ^nil ]
    ]

    lostCursor []
    gainedCursor []

    buttonPressed: aButtonNumber at: aPoint over: aWidget []
    mouseMovedTo: aPoint over: aWidget []
    buttonReleased: aButtonNumber at: aPoint over: aWidget []
    allButtonsReleasedAt: aPoint over: aWidget []

    handlesKeys [ ^false ]
    keyPressed: sym unicode: unicodeCh modifiers: modifierSet []
    keyReleased: sym unicode: unicodeCh modifiers: modifierSet []

    setHandler: aSymbol to: aBlockOrDirectedMessage [
	| handlers |
	handlers := self propertyAt: #handlers ifAbsentPut: [Dictionary new].
        aBlockOrDirectedMessage
	    ifNil: [handlers removeKey: aSymbol ifAbsent: []]
	    ifNotNil: [ :dummy | handlers at: aSymbol put: aBlockOrDirectedMessage].
	handlers isEmpty ifTrue: [self removePropertyAt: #handlers].
    ]

    runHandler: aSymbol [
	((self propertyAt: #handlers ifAbsent: [^self]) at: aSymbol ifAbsent: [^self]) value.
    ]

    selectClickedAt: aPoint [
        self runHandler: #selectClicked.
    ]

    menuClickedAt: aPoint [
        (self propertyAt: #menu ifAbsent: [^self])
	    showAt: (self deviceToLocalTransform transformPoint: aPoint).
    ]

    adjustClickedAt: aPoint [
        self showHalo.
    ]

    scrollUp [
	parent ifNotNil: [ :p | p scrollUp ].
    ]
    scrollDown [
	parent ifNotNil: [ :p | p scrollUp ].
    ]

    clicked: aButtonNumber at: aPoint [
	"Button name convention taken from RISC OS. aPoint is in local coordinates."

	aButtonNumber == 1 "left" ifTrue: [ ^ self selectClickedAt: aPoint ].
	aButtonNumber == 2 "middle" ifTrue: [ ^ self menuClickedAt: aPoint ].
	aButtonNumber == 3 "right" ifTrue: [ ^ self adjustClickedAt: aPoint ].
	aButtonNumber == 4 "scroll wheel up" ifTrue: [ ^ self scrollUp ].
	aButtonNumber == 5 "scroll wheel down" ifTrue: [ ^ self scrollDown ].
    ]

    resistsPickup [ ^true ]

    dragStarted: aButtonNumber at: aPoint over: aWidget [
	self resistsPickup ifFalse: [
	    World current activeHand activeMode: (PickupMode new moving: self at: aPoint)]
    ]

    dragReleased: aButtonNumber at: aPoint over: aWidget [
	aWidget == self ifTrue: [ self clicked: aButtonNumber at: aPoint ]
    ]

    containsWidget: aWidget [
	^ self == aWidget
    ]

    acceptsDrop: aWidget [ ^false ]
    acceptDrop: aWidget at: aPoint [
	self subclassResponsibility
    ]
].

Widget subclass: PositionableWidget [
    | localToParentTransform translation rotation |

    localToParentTransform [
	^ localToParentTransform ifNil: [
	    localToParentTransform := (Cairo.Translation by: translation) rotateBy: rotation.
	    localToParentTransform]
    ]

    translation [ ^translation ]
    translation: aPoint [ self invalidate. translation := aPoint. self moved. ]
    rotation [ ^rotation ]
    rotation: rads [ self invalidate. rotation := rads. self moved. ]

    translation: aPoint rotation: rads [
	self invalidate.
	translation := aPoint.
	rotation := rads.
	self moved.
    ]

    initialize [
	translation := 0@0.
	rotation := 0.
	super initialize.
    ]

    resetPosition [
	self translation: 0@0 rotation: 0.
    ]

    translateBy: aPoint [
	self translation:
	    self translation + (self localToParentTransform transformDistance: aPoint).
    ]

    rotateByRadians: rads [
	self rotation: self rotation + rads.
    ]

    rotateByDegrees: degs [
	^ self rotateByRadians: degs degreesToRadians
    ]

    moved [
	localToParentTransform := nil.
        self clearCachedDeviceTransform.
	self invalidate.
    ]

    resistsPickup [ ^self propertyAt: #resistsPickup ifAbsent: [true] ]
    resistsPickup: aBoolean [ ^self propertyAt: #resistsPickup put: aBoolean checkingDefault: true ]
].

PositionableWidget subclass: Container [
    | children |

    children [ ^children copy ]

    initialize [
	children := OrderedCollection new.
	super initialize.
    ]

    clearCachedDeviceTransform [
        children do: [:each | each clearCachedDeviceTransform].
        super clearCachedDeviceTransform.
    ]

    addWidget: aWidget [
	(aWidget containsWidget: self) ifTrue: [^self].

	Transcript << self << ' addWidget: ' << aWidget; nl.
	aWidget parent ifNotNil: [:p | p removeWidget: aWidget].
	children add: aWidget.
	aWidget parent: self.
	aWidget addDependent: self.
	self invalidate.
    ]

    removeWidget: aWidget [
	aWidget removeDependent: self.
	children remove: aWidget.
	self invalidate.
    ]

    containsWidget: aWidget [
	^ (super containsWidget: aWidget) or:
	    [children contains: [ :child | child containsWidget: aWidget ]]
    ]

    paintSubwidgets: aCollection on: gc [
	aCollection do: [:w | gc saveWhile: [ w paintOn: gc ]].
    ]

    paintOn: gc [
	super paintOn: gc.
	self paintSubwidgets: children on: gc.
    ]

    widgetUnder: aPoint [
	| w |
	w := super widgetUnder: aPoint.
	(w == self) ifTrue: [
	    children reverseDo: [ :child | | childPoint |
		childPoint := child parentToLocalTransform transformPoint: aPoint.
		(child widgetUnder: childPoint) ifNotNil: [ :ww | ^ww ] ]].
	^ w.
    ]

    acceptsDrop: aWidget [
	^ (aWidget containsWidget: self) not
    ]

    acceptDrop: aWidget at: aPoint [
	| originDc |
	originDc := aWidget localToDeviceTransform transformPoint: 0@0.
	self addWidget: aWidget.
	aWidget translation: (self deviceToLocalTransform transformPoint: originDc).
    ]
].

Object subclass: GestureMode [
    | hand |

    hand [ ^hand ]
    hand: aHand [ hand := aHand ]

    endMode [
	Transcript << 'endMode'; nl.
	hand activeMode: nil.
    ]

    deviceToLocalTransform [ ^ Cairo.Transform identity ]

    buttonPressed: aButtonNumber at: aPoint over: aWidget []
    mouseMovedTo: aPoint over: aWidget []
    buttonReleased: aButtonNumber at: aPoint over: aWidget []

    allButtonsReleasedAt: aPoint over: aWidget [
	self endMode.
    ]

    clicked: aButtonNumber at: aPoint []
    dragStarted: aButtonNumber at: aPoint over: aWidget []
    dragReleased: aButtonNumber at: aPoint over: aWidget []
].

GestureMode subclass: PickupMode [
    | holding offsetDc |

    moving: aWidget at: aPoint [
	| originDc |
	holding := aWidget.
	originDc := holding localToDeviceTransform transformPoint: 0@0.
	offsetDc := (holding localToDeviceTransform transformPoint: aPoint) - originDc.
	Transcript << 'originDc ' << originDc; nl.
	Transcript << 'offsetDc ' << offsetDc; nl.
	World current root overlay addWidget: holding.
	holding translation: originDc.
    ]

    mouseMovedTo: dc over: aWidget [
	holding translation: (dc - offsetDc).
    ]

    allButtonsReleasedAt: aPoint over: aWidget [
	| target |
	target := aWidget.
	[ Transcript << 'Considering target ' << target; nl.
	  target ifNil: [
	    self undoPickup.
	    ^ self endMode].
	  target acceptsDrop: holding ] whileFalse: [ target := target parent. ].
	target acceptDrop: holding at: aPoint.
	self endMode.
    ]
].

Container subclass: Box [
    | extent |

    extent [ ^extent ]
    extent: aPoint [ extent := aPoint ]

    paintSubwidgets: aCollection on: gc [
	gc saveWhile: [
	    gc
		newPath;
		rectangle: self localBounds;
		clip.
	    super paintSubwidgets: aCollection on: gc].
    ]

    localBounds [
	^ 0@0 extent: extent
    ]
].

Container subclass: RootWidget [
    | overlay |

    overlay [ ^overlay ]

    localBounds [
	^ 0@0 extent: Display extent
    ]

    initialize [
	overlay := Box new.
	overlay extent: Display extent.
	super initialize.
    ]

    paintOn: gc [
	gc
	    source: Cairo.Color black;
	    paint.
	super paintOn: gc.
	overlay paintOn: gc.
    ]

    handlesKeys [ ^true ]
    keyPressed: sym unicode: unicodeCh modifiers: modifierSet [
        ((sym = $f) and: [modifierSet includes: #ctrl]) ifTrue: [
            Transcript << 'toggling: ' << Display toggleFullscreen; nl. ].
        ((sym = $q) and: [modifierSet includes: #ctrl]) ifTrue: [
            World current handleWMQuitRequest ].
    ]
    keyReleased: sym unicode: unicodeCh modifiers: modifierSet []
].

Object subclass: Painter [
    Painter class >> new [
	^ super new initialize
    ]

    initialize [
    ]

    paint: aWidget on: gc [
	self subclassResponsibility.
    ]
].

Painter subclass: CompositePainter [
    | steps |

    steps [ ^steps ]
    steps: aCollection [ steps := aCollection ]

    initialize [
	steps := OrderedCollection new.
	super initialize.
    ]

    paint: aWidget on: gc [
	steps do: [ :each | each paint: aWidget on: gc ]
    ]
].

Painter subclass: FilledBorderedPainter [
    | borderColor borderWidth fillColor |

    borderColor [ ^ borderColor ]
    borderColor: aColor [ borderColor := aColor ]
    borderWidth [ ^ borderWidth ]
    borderWidth: aNumber [ borderWidth := aNumber ]
    fillColor [ ^fillColor ]
    fillColor: aColor [ fillColor := aColor ]

    initialize [
	self borderColor: Cairo.Color black.
	self borderWidth: 1.
	self fillColor: Cairo.Color red.
	super initialize.
    ]

    drawBorderPathFor: aWidget on: gc [
	self subclassResponsibility.
    ]

    paint: aWidget on: gc [
	| c |
	gc newPath.
	self drawBorderPathFor: aWidget on: gc.
	self fillColor ifNotNil: [ :c | gc source: c; fillPreserve].
	borderWidth > 0 ifTrue: [
	    gc
		source: self borderColor;
		lineWidth: borderWidth;
		strokePreserve].
    ]
].

"This shouldn't survive long - should be replaced with a sensible general text widget."
PositionableWidget subclass: LabelWidget [
    | extent label style |

    label [ ^label ]
    label: aString [ label := aString ]
    style [ ^ style ifNil: [ TextStyle default ] ]
    style: aStyle [ style := aStyle ]

    initialize [
	label := ''.
	extent := 0.
	style := nil.
	super initialize.
    ]

    localBounds [
	^ 0@0 extent: extent
    ]

    paintSelfOn: gc [
	| e l |
	gc newPath.
	self style applyTo: gc.
	l := self label.
	e := gc textExtents: l.
	extent := e extent.
	gc
	    translateBy: e bearing * -1;
	    showText: l.
    ]
].

FilledBorderedPainter subclass: RectanglePainter [
    drawBorderPathFor: aWidget on: gc [
	gc rectangle: (aWidget localBounds insetBy: (self borderWidth / 2) asFloat).
    ]
].

FilledBorderedPainter subclass: RoundedRectanglePainter [
    | cornerRadius |

    cornerRadius [ ^cornerRadius ]
    cornerRadius: aNumber [ cornerRadius := aNumber ]

    drawBorderPathFor: aWidget on: gc [
	gc roundedRectangle: (aWidget localBounds insetBy: (self borderWidth / 2) asFloat)
           radius: cornerRadius.
    ]
].

PositionableWidget subclass: TextWidget [
    | paragraph extent composition selectedPos selectedRect |

    paragraph [ ^paragraph ]
    paragraph: aParagraph [ paragraph := aParagraph ]

    extent [ ^extent ]
    extent: aPoint [ extent := aPoint ]

    localBounds [ ^ 0@0 extent: extent ]

    handlesKeys [ ^self editable ]

    editable [ ^self propertyAt: #editable ifAbsent: [true] ]
    editable: aBoolean [ ^self propertyAt: #editable put: aBoolean checkingDefault: true ]

    keyPressed: sym unicode: unicodeCh modifiers: modifierSet [
	Transcript << 'TW key down: ' << sym << ' ' << unicodeCh << ' ' << modifierSet; nl.
	unicodeCh asciiValue > 0 ifTrue: [
	    selectedRect ifNotNil: [
		Transcript << 'Would insert text ''' << unicodeCh << '''.'; nl]].
    ]
    keyReleased: sym unicode: unicodeCh modifiers: modifierSet [
	Transcript << 'TW key   up: ' << sym << ' ' << unicodeCh << ' ' << modifierSet; nl.
    ]

    lostCursor [ Transcript << 'TW lostCursor'; nl ]
    gainedCursor [ Transcript << 'TW gainedCursor'; nl ]

    clicked: aButtonNumber at: aPoint [
	| pos |
	Transcript << 'TW clicked: ' << aButtonNumber << ' at: ' << aPoint; nl.
	Transcript << '   position: ' << (pos := composition positionAtPoint: aPoint); nl.
	selectedPos := pos.
	pos ifNil: [selectedRect := nil]
	    ifNotNil: [selectedRect := (composition rectangleAtPosition: pos)].
	self invalidate.
	^ super clicked: aButtonNumber at: aPoint.
    ]

    paintSelfOn: gc [
	super paintSelfOn: gc.
	self paintTextOn: gc.
    ]

    paintTextOn: gc [
	| b |
	b := self localBounds.
	gc moveTo: b origin.
	gc newPath; rectangle: b; clip.

	gc saveWhile: [
	    composition := paragraph composeUsing: gc width: b width.
	    composition renderOn: gc.
	].

	selectedRect ifNotNil: [
	    gc saveWhile: [
		gc newPath.
		gc source: (Cairo.Color blue withAlpha: 0.2).
		gc rectangle: selectedRect; fill.
	    ].
	].
    ]
].

PositionableWidget subclass: DemoWidget [
    "Just some test methods."

    | extent |

    initialize [
	super initialize.
	self resistsPickup: false.
    ]

    extent: aPoint [ extent := aPoint ]
    localBounds [ ^ 0@0 extent: extent ]

    handlesKeys [ ^true ]

    keyPressed: sym unicode: unicodeCh modifiers: modifierSet [
	Transcript << 'key down: ' << sym << ' ' << unicodeCh << ' ' << modifierSet; nl.
    ]
    keyReleased: sym unicode: unicodeCh modifiers: modifierSet [
	Transcript << 'key   up: ' << sym << ' ' << unicodeCh << ' ' << modifierSet; nl.
    ]

    lostCursor [ Transcript << 'lostCursor'; nl ]
    gainedCursor [ Transcript << 'gainedCursor'; nl ]

    clicked: aButtonNumber at: aPoint [
	Transcript << 'clicked: ' << aButtonNumber << ' at: ' << aPoint; nl.
	^ super clicked: aButtonNumber at: aPoint.
    ]

    dragStarted: aButtonNumber at: aPoint over: aWidget [
	Transcript << 'dragStarted: ' << aButtonNumber << ' at: ' << aPoint << ' over: ' << aWidget; nl.
	Transcript << ' -- other''s local ' << (aWidget deviceToLocalTransform transformPoint: (self localToDeviceTransform transformPoint: aPoint)); nl.
	^ super dragStarted: aButtonNumber at: aPoint over: aWidget.
    ]

    dragReleased: aButtonNumber at: aPoint over: aWidget [
	Transcript << 'dragReleased: ' << aButtonNumber << ' at: ' << aPoint << ' over: ' << aWidget; nl.
	Transcript << ' -- other''s local ' << (aWidget deviceToLocalTransform transformPoint: (self localToDeviceTransform transformPoint: aPoint)); nl.
	^ super dragReleased: aButtonNumber at: aPoint over: aWidget.
    ]
]

Object subclass: World [
    | cairoSurface context root recogniser renderSemaphore invalidRect refreshPauseCount renderProcess |

    recogniser [ ^recogniser ]
    root [ ^root ]

    initialize [
	root := RootWidget new.

	recogniser := GestureRecogniser new target: self.
	Display eventSource handler: recogniser; startEventLoop.

	cairoSurface := Cairo.CairoSdlSurface on: Display.

	"We save away one long-lived context here, even though
	we are creating and releasing a context each rerendering
	by using withContextDo: below. The long-lived context is
	saved away by ParagraphComposition for text metrics calculation.
	Gross! FIXME"
	context := Cairo.CairoContext on: cairoSurface.

	renderSemaphore := Semaphore forMutualExclusion.
	invalidRect := nil.
	refreshPauseCount := 0.

	renderSemaphore name: 'World renderSemaphore'.

	renderProcess := [ self renderLoop ] fork.
	renderProcess terminateOnQuit.
	renderProcess name: 'World renderLoop'.
    ]

    resume [
	"Used to get rid of the CallinProcess that is the command-line
	 shell. Does not return.  It will block forever. An image save
	 will not save the blocked process."

	Semaphore new wait.
    ]

    widgetUnderHand: aHand at: devicePoint [
	^ root widgetUnder: (root deviceToLocalTransform transformPoint: devicePoint).
    ]

    activeHand [
	^ recogniser activeHand
    ]

    invalidate: aRectangle [
	renderSemaphore critical: [
	    invalidRect := invalidRect
				ifNil: [ aRectangle ]
				ifNotNil: [ :r | r merge: aRectangle ]]
    ]

    pauseRefresh [
	renderSemaphore critical: [
	    refreshPauseCount := refreshPauseCount + 1]
    ]

    unpauseRefresh [
	renderSemaphore critical: [
	    refreshPauseCount := (refreshPauseCount - 1) max: 0]
    ]

    pauseRefreshDuring: aBlock [
        self pauseRefresh.
	^ aBlock ensure: [self unpauseRefresh]
    ]

    renderLoop [
	| d r |
	d := Delay forMilliseconds: 30.
	[
	    renderSemaphore critical: [
		refreshPauseCount > 0
		    ifTrue: [ r := nil ]
		    ifFalse: [ r := invalidRect. invalidRect := nil ]].
	    r ~~ nil ifTrue: [
		Transcript << (Time millisecondsToRun: [
                    cairoSurface withContextDo: [ :disposableContext |
                        "We ignore the disposableContext and use our
                        premade context instead, so that ParagraphComposition
                        gets to keep an object that it can safely assume
                        will outlive just this single rendering. The reason
                        we call withContextDo: in the first place, rather
                        than just Display>>critical:, is that Cairo SDL
                        surfaces built on top of OpenGL need special treatment
                        which is encapsulated in their withContextDo:
                        implementation."
                        context
				resetClip;
				newPath;
				rectangle: (r rounded expandBy: 1);
				clip.
			context saveWhile: [root paintOn: context]]]); nl.
	    ].
	    d wait.
	] repeat.
    ]

    handleWMQuitRequest [
	ObjectMemory quit.
    ]
].

Cairo.CairoContext extend [
    roundedRectangle: b radius: cornerRadius [
	| hr vr h2 v2 |
	hr := cornerRadius@0.
	vr := 0@cornerRadius.
	h2 := hr * (1 - 0.55228475).
	v2 := vr * (1 - 0.55228475).
	self
	    moveTo: b topLeft + hr;
	    lineTo: b topRight - hr;
	    curveTo: b topRight + vr via: b topRight - h2 via: b topRight + v2;
	    lineTo: b bottomRight - vr;
	    curveTo: b bottomRight - hr via: b bottomRight - v2 via: b bottomRight - h2;
	    lineTo: b bottomLeft + hr;
	    curveTo: b bottomLeft - vr via: b bottomLeft + h2 via: b bottomLeft - v2;
	    lineTo: b topLeft + vr;
	    curveTo: b topLeft + hr via: b topLeft + v2 via: b topLeft + h2.
    ]
].

World class extend [
    | current |

    current [ ^current ]

    initialize [
	current := World new initialize.
    ]
].

Object subclass: MockDisplay [
    extent [ ^480@640 ]
    critical: aBlock [ ^ aBlock value ]
    flip []
].
World extend [
    context: aContext [ context := aContext ]
].
Object subclass: MockContext [
    saveWhile: aBlock [ ^ aBlock value ]
    source: aSource []
    newPath []
    fill []
    stroke []
    fillPreserve []
    strokePreserve []
    sourceRed: r green: g blue: b []
    sourceRed: r green: g blue: b alpha: a []
    lineWidth: w []
    moveTo: aPoint []
    moveRel: aPoint []
    lineTo: aPoint []
    lineRel: aPoint []
    curveTo: aPoint3 via: aPoint1 via: aPoint2 []
    arc: aPoint radius: r from: angle1 to: angle2 []
    arcNegative: aPoint radius: r from: angle1 to: angle2 []
    rectangle: aRect []
    roundedRectangle: b radius: cornerRadius []
    clip []
    clipPreserve []
    resetClip []
    paint []
    paintWithAlpha: a []
    identityMatrix []
    translateBy: aPoint []
    scaleBy: aPoint []
    rotateBy: rads []
    nullTransform []
    transformBy: aTransform []
    selectFontFamily: aString slant: slantSymbol weight: weightSymbol []
    fontSize: aNumber []
    showText: aString []
    textPath: aString []
    textExtents: aString [ ^ MockExtents new ]
].
Object subclass: MockExtents [
    bearing [ ^ 0@0 ]
    extent [ ^ 100@20 ]
    advance [ ^ 5@5 ]
].

Object subclass: Spinner [
    | widget step delay process |
    widget [ ^widget ]
    widget: aWidget [ widget := aWidget ]
    step [ ^step ]
    step: aNumber [ step := aNumber ]
    delay [ ^delay ]
    delay: aDelay [ delay := aDelay ]

    start [
        process ifNil: [
	    process := [ [ widget rotateByDegrees: step. delay wait ] repeat ] fork].
    ]

    stop [
        process ifNotNil: [ :p |
            process terminate.
            process := nil].
    ]
].

Eval [| r1 r2 r3 iw sp para tstyle |
    World initialize.
    World current pauseRefresh.

"
    Display := MockDisplay new.
    World current context: MockContext new.
"
    World current root addWidget: (DemoWidget new
				       extent: 40@40;
				       translateBy: 50@50;
				       painter: (RectanglePainter new fillColor: Cairo.Color cyan)).

    r1 := DemoWidget new
	extent: 100@60;
	translateBy: 50@50;
	rotateByDegrees: -60;
	painter: (RoundedRectanglePainter new
		      cornerRadius: 20;
		      borderColor: Cairo.Color white;
		      borderWidth: 3;
		      fillColor: ((Cairo.LinearGradient from: 0@0 to: 100@60)
				      addStopAt: 0 color: (Cairo.Color red withAlpha: 0.2);
				      addStopAt: 1 color: Cairo.Color white)).

    r2 := DemoWidget new
	extent: 100@60;
	translateBy: 250@150;
	rotateByDegrees: 60;
	painter: (RoundedRectanglePainter new
		      cornerRadius: 20;
		      borderColor: Cairo.Color white;
		      borderWidth: 3;
		      fillColor: ((Cairo.LinearGradient from: 0@0 to: 100@60)
				      addStopAt: 0 color: (Cairo.Color blue withAlpha: 0.2);
				      addStopAt: 1 color: Cairo.Color white)).

    r3 := DemoWidget new
	extent: 100@60;
	translateBy: 250@150;
	rotateByDegrees: 180;
	painter: (RoundedRectanglePainter new
		      cornerRadius: 20;
		      borderColor: Cairo.Color white;
		      borderWidth: 3;
		      fillColor: ((Cairo.LinearGradient from: 0@0 to: 100@60)
				      addStopAt: 0 color: (Cairo.Color green withAlpha: 0.2);
				      addStopAt: 1 color: Cairo.Color white)).

    World current root addWidget: r1.
    World current root addWidget: r2.
    World current root addWidget: r3.

    World current root addWidget:
	(iw := Box new
	     extent: 128@128;
	     resistsPickup: false;
	     painter: (CompositePainter new
			steps: {RectanglePainter new fillColor: Cairo.Color red.
				RectanglePainter new fillColor: (Cairo.SurfacePattern new surface:
				    (Cairo.CairoPngSurface
					on: 'openmoko-dialer.png'))})).
    sp := Spinner new
	widget: iw;
	step: 2;
	delay: (Delay forMilliseconds: 10).
    World current root addWidget:
	(Box new
	    extent: 50@50;
	    translateBy: 50@400;
	    painter: (RectanglePainter new fillColor: Cairo.Color red);
	    setHandler: #selectClicked to: [sp stop]).
    World current root addWidget:
	(Box new
	    extent: 50@50;
	    translateBy: 100@400;
	    painter: (RectanglePainter new fillColor: Cairo.Color green);
	    setHandler: #selectClicked to: [sp start]).
    World current root addWidget:
	(Box new
	    extent: 50@50;
	    translateBy: 150@400;
	    painter: (RectanglePainter new fillColor: Cairo.Color blue)).

    World current root addWidget: (LabelWidget new
				       resistsPickup: false;
				       style: (TextStyle new
						   color: (Cairo.Color yellow withAlpha: 0.6);
						   family: 'sans-serif';
						   slant: #italic;
						   fontSize: 24;
						   weight: #bold);
				       translateBy: 40@80;
				       label: 'Hello, world!';
				       yourself).

    World current root addWidget: (LabelWidget new
				       resistsPickup: true;
				       style: (TextStyle new
						   color: (Cairo.Color red);
						   fontSize: 24;
						   family: 'sans-serif');
				       translateBy: 0@(Display extent y);
				       rotateByDegrees: -90;
				       label: 'Ctl-q to quit';
				       yourself).

    tstyle := TextStyle new family: 'freesans'; color: Cairo.Color black; yourself.
    para := Paragraph new.
    para append: ('Hello, world! This is a ' withStyle: tstyle).
    para append: ('test of Paragraph Wrapping'
		      withStyle: (TextStyle new family: 'freesans'; fontSize: 18;
				      color: Cairo.Color blue)).
    para append: (' and line layout.
DoDoDo
ReReRe 0123456789012345678901234567890123456789
MiMiMi
SHOUTY SHOUTY SHOUTY SHOUTY SHOUTY SHOUTY SHOUTY SHOUTY SHOUTY.
It was a dark and stormy night;  the rain fell in torrents--except at occasional intervals, when it was checked by a violent gust of wind which swept up the streets (for it is in London that our scene lies), rattling along the housetops, and fiercely agitating the scanty flame of the lamps that struggled against the darkness.' withStyle: tstyle).

    World current root addWidget:
	(TextWidget new
	     paragraph: para;
	     extent: 270@170;
	     translateBy: 10@150;
	     painter: (RectanglePainter new fillColor: Cairo.Color white)).

    World current root addWidget:
	(TextWidget new
	     paragraph: (Paragraph new append: 'A short

paragraph'; yourself);
	     extent: 270@170;
	     translateBy: 310@150;
	     painter: (RectanglePainter new fillColor: Cairo.Color white)).

    World current root painter: (RectanglePainter new
				     borderWidth: 0;
				     fillColor:
					 ((Cairo.LinearGradient
						from: 0@(Display extent y - 280)
						to: 0@(Display extent y - 80))
					      addStopAt: 0 color: Cairo.Color blue * 0.2;
					      addStopAt: 1 color: Cairo.Color white)).
    World current root invalidate.

    World current unpauseRefresh.
    World current resume.
].
