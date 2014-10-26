FT_CFLAGS=`freetype-config --cflags`
CAIRO_CFLAGS=`pkg-config --cflags cairo`

FT_LDFLAGS=`freetype-config --libs`
CAIRO_LDFLAGS=`pkg-config --libs cairo`

chew: chew.c
	$(CC) $(FT_CFLAGS) $(CAIRO_CFLAGS) -o $@ $< $(FT_LDFLAGS) $(CAIRO_LDFLAGS)

TTFS=$(shell find . -iname '*.ttf')
GZS=$(patsubst %.ttf,%.gz,$(TTFS))

dest: gzs
	mkdir dest
	cp -p $(GZS) dest

gzs: $(GZS)

%.gz: %.ttf
	./chew $< | gzip -c > $@

clean:
	rm -f chew
