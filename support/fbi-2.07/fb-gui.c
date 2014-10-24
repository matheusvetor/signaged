#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <wchar.h>
#include <inttypes.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

#include "fbtools.h"
#include "dither.h"
#include "fb-gui.h"

/* public */
int visible = 1;

static int ys =  3;
static int xs = 10;

/* ---------------------------------------------------------------------- */
/* shadow framebuffer -- internals                                        */

static float p_gamma = 1;
static unsigned short p_red[256], p_green[256], p_blue[256];
static struct fb_cmap p_cmap = { 0, 256, p_red, p_green, p_blue };

static int32_t s_lut_transp[256], s_lut_red[256], s_lut_green[256], s_lut_blue[256];

static unsigned char **shadow;
static unsigned int  *sdirty,swidth,sheight;

static unsigned short calc_gamma(int n, int max)
{
    int ret = 65535.0 * pow((float)n/(max), 1 / p_gamma);
    if (ret > 65535) ret = 65535;
    if (ret <     0) ret =     0;
    return ret;
}

static void
linear_palette(int r, int g, int b)
{
    int i, size;
    
    size = 256 >> (8 - r);
    for (i = 0; i < size; i++)
        p_red[i] = calc_gamma(i,size);
    p_cmap.len = size;

    size = 256 >> (8 - g);
    for (i = 0; i < size; i++)
        p_green[i] = calc_gamma(i,size);
    if (p_cmap.len < size)
	p_cmap.len = size;

    size = 256 >> (8 - b);
    for (i = 0; i < size; i++)
	p_blue[i] = calc_gamma(i,size);
    if (p_cmap.len < size)
	p_cmap.len = size;
}

static void
dither_palette(int r, int g, int b)
{
    int             rs, gs, bs, i;

    rs = 256 / (r - 1);
    gs = 256 / (g - 1);
    bs = 256 / (b - 1);
    for (i = 0; i < 256; i++) {
	p_red[i]   = calc_gamma(rs * ((i / (g * b)) % r), 255);
	p_green[i] = calc_gamma(gs * ((i / b) % g),       255);
	p_blue[i]  = calc_gamma(bs * ((i) % b),           255);
    }
    p_cmap.len = 256;
}

static void shadow_lut_init_one(int32_t *lut, int bits, int shift)
{
    int i;
    
    if (bits > 8)
	for (i = 0; i < 256; i++)
	    lut[i] = (i << (bits + shift - 8));
    else
	for (i = 0; i < 256; i++)
	    lut[i] = (i >> (8 - bits)) << shift;
}

static void shadow_lut_init(int depth)
{
    if (fb_var.red.length   &&
	fb_var.green.length &&
	fb_var.blue.length) {
	/* fb_var.{red|green|blue} looks sane, use it */
	shadow_lut_init_one(s_lut_transp, fb_var.transp.length, fb_var.transp.offset);
	shadow_lut_init_one(s_lut_red,   fb_var.red.length,   fb_var.red.offset);
	shadow_lut_init_one(s_lut_green, fb_var.green.length, fb_var.green.offset);
	shadow_lut_init_one(s_lut_blue,  fb_var.blue.length,  fb_var.blue.offset);
    } else {
	/* fallback */
	int i;
	switch (depth) {
	case 15:
	    for (i = 0; i < 256; i++) {
		s_lut_red[i]   = (i & 0xf8) << 7;	/* bits -rrrrr-- -------- */
		s_lut_green[i] = (i & 0xf8) << 2;	/* bits ------gg ggg----- */
		s_lut_blue[i]  = (i & 0xf8) >> 3;	/* bits -------- ---bbbbb */
	    }
	    break;
	case 16:
	    for (i = 0; i < 256; i++) {
		s_lut_red[i]   = (i & 0xf8) << 8;	/* bits rrrrr--- -------- */
		s_lut_green[i] = (i & 0xfc) << 3;	/* bits -----ggg ggg----- */
		s_lut_blue[i]  = (i & 0xf8) >> 3;	/* bits -------- ---bbbbb */
	    }
	    break;
	case 32:
	    for (i = 0; i < 256; i++) {
		s_lut_transp[i] = i << 24;		/* byte a--- */
	    }
	case 24:
	    for (i = 0; i < 256; i++) {
		s_lut_red[i]   = i << 16;	        /* byte -r-- */
		s_lut_green[i] = i << 8;                /* byte --g- */
		s_lut_blue[i]  = i;	                /* byte ---b */
	    }
	    break;
	}
    }
}

static void shadow_render_line(int line, unsigned char *dest, char unsigned *buffer)
{
    uint8_t  *ptr  = (void*)dest;
    uint16_t *ptr2 = (void*)dest;
    uint32_t *ptr4 = (void*)dest;
    int x;

    switch (fb_var.bits_per_pixel) {
    case 8:
	dither_line(buffer, ptr, line, swidth);
	break;
    case 15:
    case 16:
	for (x = 0; x < swidth; x++) {
	    ptr2[x] = s_lut_red[buffer[x*3]] |
		s_lut_green[buffer[x*3+1]] |
		s_lut_blue[buffer[x*3+2]];
	}
	break;
    case 24:
	for (x = 0; x < swidth; x++) {
	    ptr[3*x+2] = buffer[3*x+0];
	    ptr[3*x+1] = buffer[3*x+1];
	    ptr[3*x+0] = buffer[3*x+2];
	}
	break;
    case 32:
	for (x = 0; x < swidth; x++) {
	    ptr4[x] = s_lut_transp[255] |
		s_lut_red[buffer[x*3]] |
		s_lut_green[buffer[x*3+1]] |
		s_lut_blue[buffer[x*3+2]];
	}
	break;
    }
}

/* ---------------------------------------------------------------------- */
/* shadow framebuffer -- management interface                             */

void shadow_render(void)
{
    unsigned int offset = 0;
    int i;

    if (!visible)
	return;
    for (i = 0; i < sheight; i++, offset += fb_fix.line_length) {
	if (0 == sdirty[i])
	    continue;
	shadow_render_line(i, fb_mem + offset, shadow[i]);
	sdirty[i] = 0;
    }
}

void shadow_clear_lines(int first, int last)
{
    int i;

    for (i = first; i <= last; i++) {
	memset(shadow[i],0,3*swidth);
	sdirty[i]++;
    }
}

void shadow_clear(void)
{
    shadow_clear_lines(0, sheight-1);
}

void shadow_set_dirty(void)
{
    int i;

    for (i = 0; i < sheight; i++)
	sdirty[i]++;
}

void shadow_set_palette(int fd)
{
    if (fb_fix.visual != FB_VISUAL_DIRECTCOLOR && fb_var.bits_per_pixel != 8)
	return;
    if (-1 == ioctl(fd,FBIOPUTCMAP,&p_cmap)) {
	perror("ioctl FBIOPUTCMAP");
	exit(1);
    }
}

void shadow_init(void)
{
    int i;

    /* init shadow fb */
    swidth  = fb_var.xres;
    sheight = fb_var.yres;
    shadow  = malloc(sizeof(unsigned char*) * sheight);
    sdirty  = malloc(sizeof(unsigned int)   * sheight);
    memset(sdirty,0, sizeof(unsigned int)   * sheight);
    for (i = 0; i < sheight; i++)
	shadow[i] = malloc(swidth*3);
    shadow_clear();

    /* init rendering */
    switch (fb_var.bits_per_pixel) {
    case 8:
	dither_palette(8, 8, 4);
	init_dither(8, 8, 4, 2);
	dither_line = dither_line_color;
	break;
    case 15:
    case 16:
	if (fb_var.green.length == 5) {
	    shadow_lut_init(15);
	    if (fb_fix.visual == FB_VISUAL_DIRECTCOLOR)
		linear_palette(5,5,5);
	} else {
	    shadow_lut_init(16);
	    if (fb_fix.visual == FB_VISUAL_DIRECTCOLOR)
		linear_palette(5,6,5);
	}
	break;
    case 24:
        if (fb_fix.visual == FB_VISUAL_DIRECTCOLOR)
            linear_palette(8,8,8);
	break;
    case 32:
        if (fb_fix.visual == FB_VISUAL_DIRECTCOLOR)
            linear_palette(8,8,8);
	shadow_lut_init(24);
	break;
    default:
	fprintf(stderr, "Oops: %i bit/pixel ???\n",
		fb_var.bits_per_pixel);
	exit(1);
    }
}

void shadow_fini(void)
{
    int i;

    if (!shadow)
	return;
    for (i = 0; i < sheight; i++)
	free(shadow[i]);
    free(shadow);
    free(sdirty);
}

/* ---------------------------------------------------------------------- */
/* shadow framebuffer -- drawing interface                                */

static void shadow_setpixel(int x, int y)
{
    unsigned char *dest = shadow[y] + 3*x;

    if (x < 0)
	return;
    if (x >= swidth)
	return;
    if (y < 0)
	return;
    if (y >= sheight)
	return;
    *(dest++) = 255;
    *(dest++) = 255;
    *(dest++) = 255;
    sdirty[y]++;
}

void shadow_draw_line(int x1, int x2, int y1,int y2)
{
    int x,y,h;
    float inc;

    if (x2 < x1)
	h = x2, x2 = x1, x1 = h;
    if (y2 < y1)
	h = y2, y2 = y1, y1 = h;

    if (x2 - x1 < y2 - y1) {
	inc = (float)(x2-x1)/(float)(y2-y1);
	for (y = y1; y <= y2; y++) {
	    x = x1 + inc * (y - y1);
	    shadow_setpixel(x,y);
	}
    } else {
	inc = (float)(y2-y1)/(float)(x2-x1);
	for (x = x1; x <= x2; x++) {
	    y = y1 + inc * (x - x1);
	    shadow_setpixel(x,y);
	}
    }
}

void shadow_draw_rgbdata(int x, int y, int pixels, unsigned char *rgb)
{
    unsigned char *dest = shadow[y] + 3*x;

    memcpy(dest,rgb,3*pixels);
    sdirty[y]++;
}

void shadow_merge_rgbdata(int x, int y, int pixels, int weight,
			  unsigned char *rgb)
{
    unsigned char *dest = shadow[y] + 3*x;
    int i = 3*pixels;

    weight = weight * 256 / 100;

    while (i-- > 0)
	*(dest++) += *(rgb++) * weight >> 8;
    sdirty[y]++;
}


void shadow_darkify(int x1, int x2, int y1,int y2, int percent)
{
    unsigned char *ptr;
    int x,y,h;

    if (x2 < x1)
	h = x2, x2 = x1, x1 = h;
    if (y2 < y1)
	h = y2, y2 = y1, y1 = h;
    
    if (x1 < 0)
	x1 = 0;
    if (x2 >= swidth)
	x2 = swidth;

    if (y1 < 0)
	y1 = 0;
    if (y2 >= sheight)
	y2 = sheight;

    percent = percent * 256 / 100;

    for (y = y1; y <= y2; y++) {
	sdirty[y]++;
	ptr = shadow[y];
	ptr += 3*x1;
	x = 3*(x2-x1+1);
	while (x-- > 0) {
	    *ptr = (*ptr * percent) >> 8;
	    ptr++;
	}
    }
}

/* ---------------------------------------------------------------------- */
/* clear screen (areas)                                                   */

void fb_clear_mem(void)
{
    if (visible)
	fb_memset(fb_mem,0,fb_fix.smem_len);
}

void fb_clear_screen(void)
{
    if (visible)
	fb_memset(fb_mem,0,fb_fix.line_length * fb_var.yres);
}
