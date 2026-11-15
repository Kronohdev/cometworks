class_name CwIcon
## Crisp big icons. The UI icons (ui/cometworks/icons, 32x32 SVGs) rasterize at their own 32 px;
## one drawn bigger (the agency book's hub cards draw them at 84 px) was a blurry upscale. An icon
## imported as a DPITexture (importer "svg": book, planet, star) keeps its SVG source and follows
## the window's stretch scale itself; sharpen() gives a TextureRect a copy rasterized at the size
## it is drawn. Plain CompressedTexture2D icons are left alone.

## (source DPITexture, scale) -> its rasterized copy, shared by every rect that draws it that big
static var _copies := {}


## Re-rasterizes `rect`'s DPITexture for `px` (default: its custom_minimum_size), if bigger.
static func sharpen(rect: TextureRect, px := 0.0) -> void:
	var t := rect.texture as DPITexture
	if t == null:
		return
	var src: DPITexture = t.get_meta(&"cw_icon_src", t)
	var base := maxf(src.get_size().x / maxf(src.base_scale, 0.01), 1.0)
	var want := px if px > 0.0 else maxf(rect.custom_minimum_size.x, rect.custom_minimum_size.y)
	var sc := ceilf(want / base * 4.0) / 4.0
	if sc <= src.base_scale + 0.01:
		return
	var key := [src.get_instance_id(), sc]
	var c: DPITexture = _copies.get(key)
	if c == null:
		c = src.duplicate() as DPITexture
		c.base_scale = sc
		c.set_meta(&"cw_icon_src", src)
		_copies[key] = c
	rect.texture = c


## sharpen() on every TextureRect under `root` drawn bigger than its icon.
static func sharpen_all(root: Node) -> void:
	for n in root.find_children("*", "TextureRect", true, false):
		var r := n as TextureRect
		if r.texture is DPITexture and r.expand_mode != TextureRect.EXPAND_KEEP_SIZE:
			sharpen(r)
