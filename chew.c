/* Chew up a font, spit out paths. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <errno.h>
#include <sysexits.h>

#include <ft2build.h>
#include FT_FREETYPE_H

FT_Library ft;
FT_Face face;
double em_size = 0;
char *glyph_set = NULL;

static void die(char const *format, ...) {
  va_list vl;
  va_start(vl, format);
  fprintf(stderr, "FATAL: ");
  vfprintf(stderr, format, vl);
  va_end(vl);
  exit(EX_SOFTWARE);
}

static void warn(char const *format, ...) {
  va_list vl;
  va_start(vl, format);
  fprintf(stderr, "WARNING: ");
  vfprintf(stderr, format, vl);
  va_end(vl);
}

static void info(char const *format, ...) {
  va_list vl;
  va_start(vl, format);
  fprintf(stderr, "INFO: ");
  vfprintf(stderr, format, vl);
  va_end(vl);
}

static long f2d(double f) {
  return (long) (f * 65536.0);
}

static void dump_fontinfo(void) {
  printf("familyName: '%s'\n", face->family_name);
  printf("styleName: '%s'\n", face->style_name);
  printf("ascender: %ld\n", f2d(face->ascender / em_size));
  printf("descender: %ld\n", f2d(face->descender / em_size));
  printf("height: %ld\n", f2d(face->height / em_size));
  printf("maxAdvanceWidth: %ld\n", f2d(face->max_advance_width / em_size));
  printf("maxAdvanceHeight: %ld\n", f2d(face->max_advance_height / em_size));
  printf("underlinePosition: %ld\n", f2d(face->underline_position / em_size));
  printf("underlineThickness: %ld\n", f2d(face->underline_thickness / em_size));
  printf("\n");
}

static void dump_charmap(void) {
  FT_ULong charcode;
  FT_UInt gindex;

  printf("Unicode\n");
  charcode = FT_Get_First_Char(face, &gindex);
  while (gindex) {
    printf("%lu:%u\n", charcode, gindex);
    glyph_set[gindex] = 1;
    charcode = FT_Get_Next_Char(face, charcode, &gindex);
  }
  printf("\n");
}

static void dump_kernpairs(void) {
  int glyph1, glyph2;

  printf("Kerning\n");
  for (glyph1 = 0; glyph1 < face->num_glyphs; glyph1++) {
    if (!glyph_set[glyph1]) {
      continue;
    }

    for (glyph2 = 0; glyph2 < face->num_glyphs; glyph2++) {
      FT_Vector vec;

      if (!glyph_set[glyph2]) {
	continue;
      }

      if ((errno = FT_Get_Kerning(face, glyph1, glyph2, FT_KERNING_UNSCALED, &vec))) {
	die("Failed getting kerning for glyphs %d and %d: %d\n", glyph1, glyph2, errno);
      }

      if ((vec.x != 0) || (vec.y != 0)) {
	printf("%d:%d:%ld:%ld\n", glyph1, glyph2, f2d(vec.x / em_size), f2d(vec.y / em_size));
      }
    }
  }
}

static long p2d(FT_Pos p) {
  return f2d(p / em_size);
}

static int have_currentPoint;
static FT_Vector currentPoint;

static void record_currentPoint(FT_Vector *to) {
  currentPoint = *to;
  have_currentPoint = 1;
}

static int do_move_to(FT_Vector *to, void *dummy) {
  if (have_currentPoint) {
    printf(" O");
    /* In principle, the following would help remove redundant steps: */
    /* if (currentPoint == *to) { */
    /*   return 0; */
    /* } */
  }
  printf(" M %ld %ld", p2d(to->x), p2d(to->y));
  record_currentPoint(to);
  return 0;
}

static int do_line_to(FT_Vector *to, void *dummy) {
  printf(" L %ld %ld", p2d(to->x), p2d(to->y));
  record_currentPoint(to);
  return 0;
}

static int do_conic_to(FT_Vector *control, FT_Vector *to, void *dummy) {
  /* Convert conic to cubic. Following the algorithm of cairo-ft-font.c here. */
  double x0, y0, x1, y1, x2, y2, x3, y3;

  x0 = currentPoint.x;
  y0 = currentPoint.y;

  x3 = to->x;
  y3 = to->y;

  x1 = x0 + 2.0/3.0 * (control->x - x0);
  y1 = y0 + 2.0/3.0 * (control->y - y0);

  x2 = x3 + 2.0/3.0 * (control->x - x3);
  y2 = y3 + 2.0/3.0 * (control->y - y3);

  printf(" C %ld %ld %ld %ld %ld %ld",
	 p2d(x1), p2d(y1),
	 p2d(x2), p2d(y2),
	 p2d(x3), p2d(y3));
  record_currentPoint(to);
  return 0;
}

static int do_cubic_to(FT_Vector *control1, FT_Vector *control2, FT_Vector *to, void *dummy) {
  printf(" C %ld %ld %ld %ld %ld %ld",
	 p2d(control1->x), p2d(control1->y),
	 p2d(control2->x), p2d(control2->y),
	 p2d(to->x), p2d(to->y));
  record_currentPoint(to);
  return 0;
}  

static FT_Outline_Funcs const outline_funcs = {
  (FT_Outline_MoveToFunc) do_move_to,
  (FT_Outline_LineToFunc) do_line_to,
  (FT_Outline_ConicToFunc) do_conic_to,
  (FT_Outline_CubicToFunc) do_cubic_to,
  0,
  0
};

static void dump_glyphs(void) {
  int glyph;

  for (glyph = 0; glyph < face->num_glyphs; glyph++) {
    FT_Glyph_Metrics metrics;
    int i;

    if (!glyph_set[glyph]) {
      continue;
    }

    if ((errno = FT_Load_Glyph(face, glyph,
			       FT_LOAD_NO_SCALE
			       | FT_LOAD_NO_HINTING
			       | FT_LOAD_NO_BITMAP
			       | FT_LOAD_LINEAR_DESIGN)))
      {
	die("Couldn't load glyph %d: %d\n", glyph, errno);
      }

    printf("\nGlyph %d\n", glyph);

    metrics = face->glyph->metrics;
    printf("width: %ld\n", f2d(metrics.width / em_size));
    printf("height: %ld\n", f2d(metrics.height / em_size));
    printf("horiBearingX: %ld\n", f2d(metrics.horiBearingX / em_size));
    printf("horiBearingY: %ld\n", f2d(metrics.horiBearingY / em_size));
    printf("horiAdvance: %ld\n", f2d(metrics.horiAdvance / em_size));
    printf("vertBearingX: %ld\n", f2d(metrics.vertBearingX / em_size));
    printf("vertBearingY: %ld\n", f2d(metrics.vertBearingY / em_size));
    printf("vertAdvance: %ld\n", f2d(metrics.vertAdvance / em_size));
    /* It looks like these four are the same as horiAdvance, vertAdvance: */
    /*
    printf("linearHoriAdvance: %ld\n", f2d(face->glyph->linearHoriAdvance / em_size));
    printf("linearVertAdvance: %ld\n", f2d(face->glyph->linearVertAdvance / em_size));
    printf("transformedAdvanceX: %ld\n", f2d(face->glyph->advance.x / em_size));
    printf("transformedAdvanceY: %ld\n", f2d(face->glyph->advance.y / em_size));
    */

    if (face->glyph->format != FT_GLYPH_FORMAT_OUTLINE) {
      die("Glyph %d not FT_GLYPH_FORMAT_OUTLINE\n", glyph);
    }

    printf("path:");
    /* I'd pass in NULL instead of &glyph, but it complains with
       "invalid argument" (6) if I do! */
    have_currentPoint = 0;
    currentPoint.x = 0;
    currentPoint.y = 0;
    if ((errno = FT_Outline_Decompose(&face->glyph->outline, &outline_funcs, &glyph))) {
      die("Couldn't decompose glyph %d: %d\n", glyph, errno);
    }
    printf("\n");
  }
}

int main(int argc, char *argv[]) {
  char const *fontfilename;
  int faceNumber = 0;
  int numFaces = 1;

  if (argc < 2) {
    die("usage: chew <fontfilename>\n");
    return EX_USAGE;
  }

  fontfilename = argv[1];
  info("Font file: %s\n", fontfilename);

  /*------------------------------------------------------------------------*/

  if ((errno = FT_Init_FreeType(&ft))) {
    die("Couldn't initialize freetype: %d\n", errno);
  }

  while (faceNumber < numFaces) {
    if ((errno = FT_New_Face(ft, fontfilename, faceNumber, &face))) {
      die("Couldn't load the font file: %d\n", errno);
    }

    if (faceNumber == 0) {
      numFaces = face->num_faces;
      info("Number of faces: %d\n", numFaces);
    }

    info("Processing face %d\n", faceNumber);

    if (!(face->face_flags & FT_FACE_FLAG_SCALABLE)) {
      warn("Skipping non-scalable face\n");
      goto face_done;
    }

    if (face->charmap->encoding != FT_ENCODING_UNICODE) {
      warn("Skipping non-unicode charmap\n");
      goto face_done;
    }

    if (!(face->face_flags & FT_FACE_FLAG_KERNING)) {
      warn("Face doesn't include any kerning information\n");
    }

    em_size = face->units_per_EM;
    info("units_per_EM is %g\n", em_size);

    info("Allocating space for %d glyphs\n", face->num_glyphs);
    glyph_set = calloc(face->num_glyphs + 1, 1);

    /* if ((errno = FT_Set_Pixel_Sizes(face, face->units_per_EM, face->units_per_EM))) { */
    if ((errno = FT_Set_Char_Size(face, 3 << 6, 0, 72, 0))) {
      die("Couldn't set freetype pixel sizes: %d\n", errno);
    }

    printf("%sFace %d\n", (faceNumber == 0) ? "" : "\n", faceNumber);
    dump_fontinfo();
    dump_charmap();
    dump_kernpairs();
    dump_glyphs();

  face_done:
    if (glyph_set) {
      free(glyph_set);
      glyph_set = NULL;
    }

    FT_Done_Face(face);
    faceNumber++;
  }

  return EX_OK;
}
