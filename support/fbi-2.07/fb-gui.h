
extern int visible;

void shadow_render(void);
void shadow_clear_lines(int first, int last);
void shadow_clear(void);
void shadow_set_dirty(void);
void shadow_set_palette(int fd);
void shadow_init(void);
void shadow_fini(void);

void shadow_draw_line(int x1, int x2, int y1,int y2);
void shadow_draw_rect(int x1, int x2, int y1,int y2);
void shadow_draw_rgbdata(int x, int y, int pixels,
			 unsigned char *rgb);
void shadow_merge_rgbdata(int x, int y, int pixels, int weight,
			  unsigned char *rgb);
void shadow_darkify(int x1, int x2, int y1,int y2, int percent);


void fb_clear_mem(void);
void fb_clear_screen(void);
