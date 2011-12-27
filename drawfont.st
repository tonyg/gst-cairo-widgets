FileStream fileIn: 'loadscript.st'.

TextRenderer extend [
    cartoonString: aString on: gc [
	"Draw sketch lines to visualize character metrics"
	| g |
	previousGlyph := nil.
	gc saveWhile: [
	    gc scaleBy: pixelSize @ pixelSize negated.
	    aString do: [:ch |
		g := fontFace glyphAt: ch.
		gc translateBy: (self kerningFor: g).
		gc saveWhile: [
		    gc source: (Cairo.Color blue withAlpha: 0.2).
		    gc translateBy: g horizontalBearing.
		    gc rectangle: (0@0 corner: g extent x @ g extent y negated).
		    gc fill].
		gc saveWhile: [
		    gc source: Cairo.Color yellow.
		    gc moveTo: -1 @ 0.
		    gc lineTo: (g extent x + 1) @ 0.
		    gc moveTo: 0 @ -1.
		    gc lineTo: 0 @ (g extent y + 1).
		    gc lineWidth: 2 / pixelSize.
		    gc stroke].
		gc saveWhile: [
		    gc source: Cairo.Color green.
		    gc moveTo: g advance x @ -1.
		    gc lineTo: g advance x @ (g extent y + 1).
		    gc lineWidth: 2 / pixelSize.
		    gc stroke].
		gc translateBy: g advance x @ 0]].
    ]
].

SDL.SdlDisplay defaultFormat extent: 800@480; fullScreen: false.
Eval [
    (SDL includesKey: #SdlGLDisplay)
	ifTrue: [ display := SDL.SdlGLDisplay current ]
	ifFalse: [ display := SDL.SdlDisplay current ].

    cairoSurface := Cairo.CairoSdlSurface on: display.
    cairoSurface withContextDo: [ :gc |
	gc source: Cairo.Color white;
	    rectangle: (0@0 extent: display extent);
	    fill.
    ].

    (FontFaceStream on: 'gentium-basic-italic.gz') installAll.
    (FontFaceStream on: 'gentium-basic-regular.gz') installAll.

    r := TextRenderer new pixelSize: 72;
        fontFace: (FontDirectory instance faceMatching: '*Gentium*' style: '*Italic*').
    drawItAt := [:s :where |
	cairoSurface withContextDo: [ :gc |
	    gc translateBy: where.
	    r cartoonString: s on: gc.
	    gc newPath.
	    gc source: Cairo.Color black.
	    r traceString: s on: gc.
	    gc fill.
	]].

    drawItAt value: 'Quiet 123 flip fifth stripy' value: 50@150.

    r := TextRenderer new pixelSize: 72;
        fontFace: (FontDirectory instance faceMatching: '*Gentium*' style: '*Regular*').
    drawItAt value: 'Quiet 123 flip fifth stripy' value: 50@350.

    display eventSource handler: SDL.SdlEventHandler new; startEventLoop.
].

"f := (FontFaceStream on: 'cn.gz') next"
