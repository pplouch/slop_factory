extends GdUnitTestSuite
## Covers Effects: the resource->color mapping (used throughout VFX/UI, see
## CLAUDE.md) and the swatch-texture builder that stands in for image
## assets project-wide.

func test_resource_color_maps_ore_and_its_bar_to_the_same_color() -> void:
	# See CLAUDE.md: a bar should read as "the refined version of its ore"
	# without a second color table.
	assert_that(Effects.resource_color("iron")).is_equal(Effects.resource_color("iron_bar"))
	assert_that(Effects.resource_color("gold")).is_equal(Effects.resource_color("gold_bar"))
	assert_that(Effects.resource_color("slopium")).is_equal(Effects.resource_color("slopium_bar"))


func test_resource_color_falls_back_to_white_for_unknown_type() -> void:
	assert_that(Effects.resource_color("not_a_real_resource")).is_equal(Color(1, 1, 1))


func test_make_swatch_texture_produces_an_image_of_the_requested_size_and_color() -> void:
	var tex := Effects.make_swatch_texture(Color(0.2, 0.4, 0.6), 8)
	assert_int(tex.get_width()).is_equal(8)
	assert_int(tex.get_height()).is_equal(8)
	# Compared per-channel with slack, not exact equality -- the swatch is
	# stored as an 8-bit-per-channel Image, so the round trip through
	# FORMAT_RGB8 quantizes the original float color slightly.
	var img := tex.get_image()
	for corner in [Vector2i(0, 0), Vector2i(7, 7)]:
		var pixel := img.get_pixel(corner.x, corner.y)
		assert_float(pixel.r).is_equal_approx(0.2, 0.01)
		assert_float(pixel.g).is_equal_approx(0.4, 0.01)
		assert_float(pixel.b).is_equal_approx(0.6, 0.01)
