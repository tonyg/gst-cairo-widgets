FT_CFLAGS=`freetype-config --cflags`
CAIRO_CFLAGS=`pkg-config --cflags cairo`

FT_LDFLAGS=`freetype-config --libs`
CAIRO_LDFLAGS=`pkg-config --libs cairo`

chew: chew.c
	$(CC) $(FT_CFLAGS) $(CAIRO_CFLAGS) -o $@ $< $(FT_LDFLAGS) $(CAIRO_LDFLAGS)

clean:
	rm -f chew
