extends GutTest

## Purpose: the grass blade texture must stay readable at a distance.
##
## The blades used to sample Quaternius' `Grass.png`, a palette atlas of four 28-pixel colour bands
## in the left fifth of a 512 pixel image and white everywhere else. The four grass meshes sample a
## band barely thirteen pixels wide, so from mip level four onwards a single texel straddled the
## band, its neighbours and the white fill, and a field seen from across the map turned muddy brown
## while the same grass underfoot stayed green. `grass_blades.png` carries the two bands the meshes
## actually use, each widened to own its side of the image (the split is at column 56), and is only 32
## rows tall: the blades run the whole V range over their height, so a 512-row texture let a blade a
## few pixels tall select mip six, where one texel is 64 pixels wide and straddles the split. At 32 rows
## the width sets the mip level instead, and the bands hold through every level a blade still shows at.
##
## These tests fail if the material is pointed back at an atlas, if the texture grows tall enough for the
## blades' height to pick the mip again, or if a mesh's UVs move onto a colour boundary.

## How far either side of a sampled column the colour has to stay the same. Bilinear filtering reads two
## texels, so at mip level four, where a texel is 16 pixels wide, a sample draws on up to 32 pixels around
## it; a blade has to be well under a pixel wide before its width selects a coarser level than that.
const BLEED_RADIUS: int = 32
## Rows the texture may have before the blades' height, which spans all of them, selects a coarser mip
## than their width does.
const MAX_ROWS: int = 32
## Room for the re-encode when the editor promotes the texture to VRAM Compressed on seeing it in 3D. BC1
## keeps two 5:6:5 colours per 4x4 block, and with 32 rows a block spans an eighth of the gradient, so
## neighbouring blocks land up to about a dozen levels apart. The two bands differ by 74 in red, so this
## still cannot take one band for the other.
const CHANNEL_TOLERANCE: int = 20

var _image: Image


func before_all() -> void:
	var material: ShaderMaterial = load("res://addons/weather_fx/resources/grass_material.tres") as ShaderMaterial
	var texture: Texture2D = material.get_shader_parameter(&"texture_albedo") as Texture2D
	assert_not_null(texture, "The grass material should carry a blade texture")
	_image = texture.get_image()
	if _image.is_compressed():
		_image.decompress()


func test_every_grass_mesh_samples_one_flat_colour() -> void:
	for mesh_type: int in GrassField.GRASS_MESHES:
		var mesh: Mesh = GrassField.GRASS_MESHES[mesh_type]
		var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		assert_gt(uvs.size(), 0, "Grass mesh %d should carry UVs" % mesh_type)
		var u_min: float = 1.0
		var u_max: float = 0.0
		for uv: Vector2 in uvs:
			u_min = minf(u_min, uv.x)
			u_max = maxf(u_max, uv.x)
		_assert_band_is_flat(mesh_type, u_min, u_max)


func test_the_texture_is_short_enough_that_the_width_picks_the_mip() -> void:
	assert_lte(
		_image.get_height(),
		MAX_ROWS,
		"The blades run the whole height of the texture, so every row added lets a small blade select a coarser mip"
	)


func test_the_sampler_does_not_wrap_into_the_other_band() -> void:
	var shader: Shader = load("res://addons/weather_fx/resources/grass_wind.gdshader") as Shader
	var regex := RegEx.new()
	regex.compile("uniform sampler2D texture_albedo([^;]*);")
	var declaration: RegExMatch = regex.search(shader.code)
	assert_not_null(declaration, "grass_wind.gdshader should declare texture_albedo")
	assert_string_contains(
		declaration.get_string(1),
		"repeat_disable",
		"texture_albedo must clamp, or a mip texel at the left edge wraps around to the far band"
	)


## Every pixel within [constant BLEED_RADIUS] of the columns a mesh samples must be the colour that
## mesh samples, so no mip level can average another band into it.
func _assert_band_is_flat(mesh_type: int, u_min: float, u_max: float) -> void:
	var width: int = _image.get_width()
	var height: int = _image.get_height()
	var first: int = maxi(0, int(u_min * width) - BLEED_RADIUS)
	var last: int = mini(width - 1, int(u_max * width) + BLEED_RADIUS)
	for row: int in 8:
		var y: int = mini(height - 1, row * height / 8)
		var expected: Color = _image.get_pixel(int(u_min * width), y)
		for x: int in range(first, last + 1):
			var found: Color = _image.get_pixel(x, y)
			if _channels_differ(expected, found) > CHANNEL_TOLERANCE:
				fail_test(
					"Grass mesh %d samples u %.4f-%.4f; column %d on row %d is %s, not the band's %s"
					% [mesh_type, u_min, u_max, x, y, found, expected]
				)
				return
	pass_test("Grass mesh %d samples a flat band with %d pixels of room either side" % [mesh_type, BLEED_RADIUS])


## The largest per-channel gap between two colours, in 0-255 steps.
func _channels_differ(a: Color, b: Color) -> int:
	return maxi(maxi(absi(a.r8 - b.r8), absi(a.g8 - b.g8)), absi(a.b8 - b.b8))
