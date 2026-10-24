<?php

/**
 * Retrieve information about the currently installed GD library
 * @return array an associative array. Elements of array returned by gd_info Attribute Meaning GD Version string value describing the installed libgd version. FreeType Support boolean value. TRUE if FreeType Support is installed. FreeType Linkage string value describing the way in which FreeType was ...
 */
function gd_info(): array {}

/**
 * Draws an arc
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $center_x x-coordinate of the center.
 * @param int $center_y y-coordinate of the center.
 * @param int $width The arc width.
 * @param int $height The arc height.
 * @param int $start_angle The arc start angle, in degrees.
 * @param int $end_angle The arc end angle, in degrees. 0° is located at the three-o'clock position, and the arc is drawn clockwise.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool TRUE on success or FALSE on failure.
 */
function imagearc(GdImage $image, int $center_x, int $center_y, int $width, int $height, int $start_angle, int $end_angle, int $color): bool {}

/**
 * Draw an ellipse
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $center_x x-coordinate of the center.
 * @param int $center_y y-coordinate of the center.
 * @param int $width The ellipse width.
 * @param int $height The ellipse height.
 * @param int $color The color of the ellipse. A color identifier created with imagecolorallocate.
 * @return bool TRUE on success or FALSE on failure.
 */
function imageellipse(GdImage $image, int $center_x, int $center_y, int $width, int $height, int $color): bool {}

/**
 * Draw a character horizontally
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or GdFont instance, returned by imageloadfont.
 * @param int $x x-coordinate of the start.
 * @param int $y y-coordinate of the start.
 * @param string $char The character to draw.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool TRUE on success or FALSE on failure.
 */
function imagechar(
    GdImage $image,
    GdFont|int $font,
    int $x,
    int $y,
    string $char,
    int $color
): bool {}

/**
 * Draw a character vertically
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or GdFont instance, returned by imageloadfont.
 * @param int $x x-coordinate of the start.
 * @param int $y y-coordinate of the start.
 * @param string $char The character to draw.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool TRUE on success or FALSE on failure.
 */
function imagecharup(
    GdImage $image,
    GdFont|int $font,
    int $x,
    int $y,
    string $char,
    int $color
): bool {}

/**
 * Get the index of the color of a pixel
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x x-coordinate of the point.
 * @param int $y y-coordinate of the point.
 * @return int|false the index of the color or FALSE on failure
 */
function imagecolorat(GdImage $image, int $x, int $y): int|false {}

/**
 * Allocate a color for an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @return int|false A color identifier or FALSE if the allocation failed.
 */
function imagecolorallocate(GdImage $image, int $red, int $green, int $blue): int|false {}

/**
 * Copy the palette from one image to another
 * @param resource|GdImage $dst The destination image resource.
 * @param resource|GdImage $src The source image resource.
 * @return void No value is returned.
 */
function imagepalettecopy(GdImage $dst, GdImage $src): void {}

/**
 * Create a new image from the image stream in the string
 * @param string $data A string containing the image data.
 * @return resource|GdImage|false An image resource will be returned on success. FALSE is returned if the image type is unsupported, the data is not in a recognised format, or the image is corrupt and cannot be loaded.
 */
function imagecreatefromstring(string $data): GdImage|false {}

/**
 * Get the index of the closest color to the specified color
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @return int|false the index of the closest color, in the palette of the image, to the specified one or FALSE on failure
 */
function imagecolorclosest(GdImage $image, int $red, int $green, int $blue): int {}

/**
 * Get the index of the color which has the hue, white and blackness
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @return int|false an integer with the index of the color which has the hue, white and blackness nearest the given color or FALSE on failure
 */
function imagecolorclosesthwb(GdImage $image, int $red, int $green, int $blue): int {}

/**
 * De-allocate a color for an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $color The color identifier.
 * @return bool TRUE on success or FALSE on failure.
 */
function imagecolordeallocate(GdImage $image, int $color): bool {}

/**
 * Get the index of the specified color or its closest possible alternative
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @return int|false a color index or FALSE on failure
 */
function imagecolorresolve(GdImage $image, int $red, int $green, int $blue): int {}

/**
 * Get the index of the specified color
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @return int|false the index of the specified color in the palette, -1 if the color does not exist, or FALSE on failure
 */
function imagecolorexact(GdImage $image, int $red, int $green, int $blue): int {}

/**
 * Set the color for the specified palette index
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $color An index in the palette.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @param int $alpha [optional] Value of alpha component.
 * @return bool|null The function returns null on success, or false on failure.
 */
function imagecolorset(GdImage $image, int $color, int $red, int $green, int $blue, int $alpha = 0): null|false {}

/**
 * Define a color as transparent
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $color [optional] A color identifier created with imagecolorallocate.
 * @return int The identifier of the new (or current, if none is specified) transparent color is returned. If color is not specified, and the image has no transparent color, the returned identifier will be -1.
 */
function imagecolortransparent(GdImage $image, ?int $color = null): int {}

/**
 * Find out the number of colors in an image's palette
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatefromgif.
 * @return int|false the number of colors in the specified image's palette, 0 for truecolor images, or FALSE on failure
 */
function imagecolorstotal(GdImage $image): int {}

/**
 * Get the colors for an index
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $color The color index.
 * @return array|false an associative array with red, green, blue and alpha keys that contain the appropriate values for the specified color index or FALSE on failure
 */
function imagecolorsforindex(GdImage $image, int $color): array {}

/**
 * Copy part of an image
 * @param resource|GdImage $dst_image Destination image link resource.
 * @param resource|GdImage $src_image Source image link resource.
 * @param int $dst_x x-coordinate of destination point.
 * @param int $dst_y y-coordinate of destination point.
 * @param int $src_x x-coordinate of source point.
 * @param int $src_y y-coordinate of source point.
 * @param int $src_width Source width.
 * @param int $src_height Source height.
 * @return bool true on success or false on failure.
 */
function imagecopy(GdImage $dst_image, GdImage $src_image, int $dst_x, int $dst_y, int $src_x, int $src_y, int $src_width, int $src_height): bool {}

/**
 * Copy and merge part of an image
 * @param resource|GdImage $dst_image Destination image link resource.
 * @param resource|GdImage $src_image Source image link resource.
 * @param int $dst_x x-coordinate of destination point.
 * @param int $dst_y y-coordinate of destination point.
 * @param int $src_x x-coordinate of source point.
 * @param int $src_y y-coordinate of source point.
 * @param int $src_width Source width.
 * @param int $src_height Source height.
 * @param int $pct The two images will be merged according to pct which can range from 0 to 100. When pct = 0, no action is taken, when 100 this function behaves identically to imagecopy for pallete images, while it implements alpha transparency for true colour images.
 * @return bool true on success or false on failure.
 */
function imagecopymerge(GdImage $dst_image, GdImage $src_image, int $dst_x, int $dst_y, int $src_x, int $src_y, int $src_width, int $src_height, int $pct): bool {}

/**
 * Copy and merge part of an image with gray scale
 * @param resource|GdImage $dst_image Destination image link resource.
 * @param resource|GdImage $src_image Source image link resource.
 * @param int $dst_x x-coordinate of destination point.
 * @param int $dst_y y-coordinate of destination point.
 * @param int $src_x x-coordinate of source point.
 * @param int $src_y y-coordinate of source point.
 * @param int $src_width Source width.
 * @param int $src_height Source height.
 * @param int $pct The src_im will be changed to grayscale according to pct where 0 is fully grayscale and 100 is unchanged. When pct = 100 this function behaves identically to imagecopy for pallete images, while it implements alpha transparency for true colour images.
 * @return bool true on success or false on failure.
 */
function imagecopymergegray(GdImage $dst_image, GdImage $src_image, int $dst_x, int $dst_y, int $src_x, int $src_y, int $src_width, int $src_height, int $pct): bool {}

/**
 * Copy and resize part of an image
 * @param resource|GdImage $dst_image Destination image resource.
 * @param resource|GdImage $src_image Source image resource.
 * @param int $dst_x x-coordinate of destination point.
 * @param int $dst_y y-coordinate of destination point.
 * @param int $src_x x-coordinate of source point.
 * @param int $src_y y-coordinate of source point.
 * @param int $dst_width Destination width.
 * @param int $dst_height Destination height.
 * @param int $src_width Source width.
 * @param int $src_height Source height.
 * @return bool true on success or false on failure.
 */
function imagecopyresized(GdImage $dst_image, GdImage $src_image, int $dst_x, int $dst_y, int $src_x, int $src_y, int $dst_width, int $dst_height, int $src_width, int $src_height): bool {}

/**
 * Create a new palette based image
 * @param int $width The image width.
 * @param int $height The image height.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreate(int $width, int $height): GdImage|false {}

/**
 * Create a new true color image
 * @param int $width Image width.
 * @param int $height Image height.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatetruecolor(int $width, int $height): GdImage|false {}

/**
 * Finds whether an image is a truecolor image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @return bool true if the image is truecolor, false otherwise.
 */
function imageistruecolor(GdImage $image): bool {}

/**
 * Convert a true color image to a palette image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param bool $dither Indicates if the image should be dithered - if it is true then dithering will be used which will result in a more speckled image but with better color approximation.
 * @param int $num_colors Sets the maximum number of colors that should be retained in the palette.
 * @return bool true on success or false on failure.
 */
function imagetruecolortopalette(GdImage $image, bool $dither, int $num_colors): bool {}

/**
 * Set the thickness for line drawing
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $thickness Thickness, in pixels.
 * @return bool true on success or false on failure.
 */
function imagesetthickness(GdImage $image, int $thickness): bool {}

/**
 * Draw a partial arc and fill it
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $center_x x-coordinate of the center.
 * @param int $center_y y-coordinate of the center.
 * @param int $width The arc width.
 * @param int $height The arc height.
 * @param int $start_angle The arc start angle, in degrees.
 * @param int $end_angle The arc end angle, in degrees. 0° is located at the three-o'clock position, and the arc is drawn clockwise.
 * @param int $color A color identifier created with imagecolorallocate.
 * @param int $style A bitwise OR of the following possibilities: IMG_ARC_PIE
 * @return bool true on success or false on failure.
 */
function imagefilledarc(GdImage $image, int $center_x, int $center_y, int $width, int $height, int $start_angle, int $end_angle, int $color, int $style): bool {}

/**
 * Draw a filled ellipse
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $center_x x-coordinate of the center.
 * @param int $center_y y-coordinate of the center.
 * @param int $width The ellipse width.
 * @param int $height The ellipse height.
 * @param int $color The fill color. A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagefilledellipse(GdImage $image, int $center_x, int $center_y, int $width, int $height, int $color): bool {}

/**
 * Set the blending mode for an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param bool $enable Whether to enable the blending mode or not. On true color images the default value is true otherwise the default value is false
 * @return bool true on success or false on failure.
 */
function imagealphablending(GdImage $image, bool $enable): bool {}

/**
 * Set the flag to save full alpha channel information (as opposed to single-color transparency) when saving PNG images
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param bool $enable Whether to save the alpha channel or not. Default to false.
 * @return bool true on success or false on failure.
 */
function imagesavealpha(GdImage $image, bool $enable): bool {}

/**
 * Allocate a color for an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @param int $alpha A value between 0 and 127. 0 indicates completely opaque while 127 indicates completely transparent.
 * @return int|false A color identifier or false if the allocation failed.
 */
function imagecolorallocatealpha(GdImage $image, int $red, int $green, int $blue, int $alpha): int|false {}

/**
 * Get the index of the specified color + alpha or its closest possible alternative
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @param int $alpha A value between 0 and 127. 0 indicates completely opaque while 127 indicates completely transparent.
 * @return int|false a color index or FALSE on failure
 */
function imagecolorresolvealpha(GdImage $image, int $red, int $green, int $blue, int $alpha): int {}

/**
 * Get the index of the closest color to the specified color + alpha
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @param int $alpha A value between 0 and 127. 0 indicates completely opaque while 127 indicates completely transparent.
 * @return int|false the index of the closest color in the palette or FALSE on failure
 */
function imagecolorclosestalpha(GdImage $image, int $red, int $green, int $blue, int $alpha): int {}

/**
 * Get the index of the specified color + alpha
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $red Value of red component.
 * @param int $green Value of green component.
 * @param int $blue Value of blue component.
 * @param int $alpha A value between 0 and 127. 0 indicates completely opaque while 127 indicates completely transparent.
 * @return int|false the index of the specified color+alpha in the palette of the image, -1 if the color does not exist in the image's palette, or FALSE on failure
 */
function imagecolorexactalpha(GdImage $image, int $red, int $green, int $blue, int $alpha): int {}

/**
 * Copy and resize part of an image with resampling
 * @param resource|GdImage $dst_image Destination image resource.
 * @param resource|GdImage $src_image Source image resource.
 * @param int $dst_x x-coordinate of destination point.
 * @param int $dst_y y-coordinate of destination point.
 * @param int $src_x x-coordinate of source point.
 * @param int $src_y y-coordinate of source point.
 * @param int $dst_width Destination width.
 * @param int $dst_height Destination height.
 * @param int $src_width Source width.
 * @param int $src_height Source height.
 * @return bool true on success or false on failure.
 */
function imagecopyresampled(GdImage $dst_image, GdImage $src_image, int $dst_x, int $dst_y, int $src_x, int $src_y, int $dst_width, int $dst_height, int $src_width, int $src_height): bool {}

/**
 * Rotate an image with a given angle
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param float $angle Rotation angle, in degrees.
 * @param int $background_color Specifies the color of the uncovered zone after the rotation
 * @param bool $ignore_transparent [optional] Prior to PHP 8.3 if set and non-zero, transparent colors are ignored (otherwise kept).
 * @return resource|GdImage|false the rotated image or FALSE on failure
 */
function imagerotate(
    GdImage $image,
    float $angle,
    int $background_color
): GdImage|false {}

/**
 * Should antialias functions be used or not.
 *
 * Before 7.2.0 it's only available if PHP is compiled with the bundled version of the GD library.
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param bool $enable Whether to enable antialiasing or not.
 * @return bool true on success or false on failure.
 */
function imageantialias(GdImage $image, bool $enable): bool {}

/**
 * Set the tile image for filling
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param resource|GdImage $tile The image resource to be used as a tile.
 * @return bool true on success or false on failure.
 */
function imagesettile(GdImage $image, GdImage $tile): bool {}

/**
 * Set the brush image for line drawing
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param resource|GdImage $brush An image resource.
 * @return bool true on success or false on failure.
 */
function imagesetbrush(GdImage $image, GdImage $brush): bool {}

/**
 * Set the style for line drawing
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int[] $style An array of pixel colors. You can use the IMG_COLOR_TRANSPARENT constant to add a transparent pixel.
 * @return bool true on success or false on failure.
 */
function imagesetstyle(GdImage $image, array $style): bool {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the PNG image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefrompng(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the AVIF raster image.
 * @return GdImage|false returns an image object representing the image obtained from the given filename
 * @since 8.1
 */
function imagecreatefromavif(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the GIF image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromgif(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the JPEG image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromjpeg(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the WBMP image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromwbmp(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the WebP image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 * @since 5.4
 */
function imagecreatefromwebp(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the XBM image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromxbm(string $filename): GdImage|false {}

/**
 * Create a new image from file or URL
 * @param string $filename Path to the XPM image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromxpm(string $filename): GdImage|false {}

/**
 * Create a new image from GD file or URL
 * @param string $filename Path to the GD file.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromgd(string $filename): GdImage|false {}

/**
 * Create a new image from GD2 file or URL
 * @param string $filename Path to the GD2 image.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromgd2(string $filename): GdImage|false {}

/**
 * Create a new image from a given part of GD2 file or URL
 * @param string $filename Path to the GD2 image.
 * @param int $x x-coordinate of source point.
 * @param int $y y-coordinate of source point.
 * @param int $width Source width.
 * @param int $height Source height.
 * @return resource|GdImage|false an image resource identifier on success, false on errors.
 */
function imagecreatefromgd2part(string $filename, int $x, int $y, int $width, int $height): GdImage|false {}

/**
 * Output a PNG image to either the browser or a file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly. null is invalid if the quality and filters arguments are not used.
 * @param int $quality [optional] Compression level: from 0 (no compression) to 9.
 * @param int $filters [optional] Allows reducing the PNG file size. It is a bitmask field which may be set to any combination of the PNG_FILTER_XXX constants. PNG_NO_FILTER or PNG_ALL_FILTERS may also be used to respectively disable or activate all filters.
 * @return bool true on success or false on failure.
 * @throws \ValueError Throws a ValueError if quality is invalid.
 */
function imagepng(GdImage $image, $file = null, int $quality = -1, int $filters = -1): bool {}

/**
 * Output a WebP image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param resource|string|null $file [optional] The path or an open stream resource (which is automatically closed after this function returns) to save the file to. If not set or null, the raw image stream will be output directly.
 * @param int $quality [optional] quality ranges from 0 (worst quality, smaller file) to 100 (best quality, biggest file).
 * @return bool true on success or false on failure.
 * @since 5.4
 * @throws \ValueError Throws a ValueError if quality is invalid.
 */
function imagewebp(GdImage $image, $file = null, int $quality = -1): bool {}

/**
 * Output image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly.
 * @return bool true on success or false on failure.
 */
function imagegif(GdImage $image, $file = null): bool {}

/**
 * Output image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly. To skip this argument in order to provide the quality parameter, use null.
 * @param int $quality [optional] quality is optional, and ranges from 0 (worst quality, smaller file) to 100 (best quality, biggest file). The default is the default IJG quality value (about 75).
 * @return bool true on success or false on failure.
 * @throws \ValueError Throws a ValueError if quality is invalid.
 */
function imagejpeg(GdImage $image, $file = null, int $quality = -1): bool {}

/**
 * Output image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly.
 * @param int $foreground_color [optional] You can set the foreground color with this parameter by setting an identifier obtained from imagecolorallocate. The default foreground color is black.
 * @return bool true on success or false on failure.
 */
function imagewbmp(GdImage $image, $file = null, ?int $foreground_color = null): bool {}

/**
 * Output GD image to browser or file.
 *
 * Since 7.2.0 allows to output truecolor images.
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string|null $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly.
 * @return bool true on success or false on failure.
 */
function imagegd(GdImage $image, ?string $file = null): bool {}

/**
 * Output GD2 image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string|null $file [optional] The path to save the file to. If not set or null, the raw image stream will be outputted directly.
 * @param int $chunk_size [optional] Chunk size.
 * @param int $mode [optional] Either IMG_GD2_RAW or IMG_GD2_COMPRESSED. Default is IMG_GD2_RAW.
 * @return bool true on success or false on failure.
 */
function imagegd2(GdImage $image, ?string $file = null, int $chunk_size = 128, int $mode = IMG_GD2_RAW): bool {}

/**
 * Destroy an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @return bool true on success or false on failure.
 */
function imagedestroy(GdImage $image): bool {}

/**
 * Apply a gamma correction to a GD image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param float $input_gamma The input gamma.
 * @param float $output_gamma The output gamma.
 * @return bool true on success or false on failure.
 */
function imagegammacorrect(GdImage $image, float $input_gamma, float $output_gamma): bool {}

/**
 * Flood fill
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x x-coordinate of start point.
 * @param int $y y-coordinate of start point.
 * @param int $color The fill color. A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagefill(GdImage $image, int $x, int $y, int $color): bool {}

/**
 * Draw a filled polygon
 * @param resource|GdImage $image
 * @param int[] $points An array containing the x and y coordinates of the polygons vertices consecutively.
 * @param int $num_points_or_color Total number of vertices, which must be at least 3.
 * @param int|null $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagefilledpolygon(
    GdImage $image,
    array $points,
    int $num_points_or_color,
    ?int $color = null
): bool {}

/**
 * Draw a filled rectangle
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x1 x-coordinate for point 1.
 * @param int $y1 y-coordinate for point 1.
 * @param int $x2 x-coordinate for point 2.
 * @param int $y2 y-coordinate for point 2.
 * @param int $color The fill color. A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagefilledrectangle(GdImage $image, int $x1, int $y1, int $x2, int $y2, int $color): bool {}

/**
 * Flood fill to specific color
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x x-coordinate of start.
 * @param int $y y-coordinate of start.
 * @param int $border_color The border color. A color identifier created with imagecolorallocate.
 * @param int $color The fill color. A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagefilltoborder(GdImage $image, int $x, int $y, int $border_color, int $color): bool {}

/**
 * Get font width
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or GdFont instance, returned by imageloadfont.
 * @return int the width of the pixel
 */
function imagefontwidth(GdFont|int $font): int {}

/**
 * Get font height
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or GdFont instance, returned by imageloadfont.
 * @return int the height of the pixel.
 */
function imagefontheight(GdFont|int $font): int {}

/**
 * Enable or disable interlace
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param bool|null $enable [optional] If non-zero, the image will be interlaced, else the interlace bit is turned off.
 * @return bool 1 if the interlace bit is set for the image, 0 if it is not
 */
function imageinterlace(GdImage $image, ?bool $enable = null): bool {}

/**
 * Draw a line
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x1 x-coordinate for first point.
 * @param int $y1 y-coordinate for first point.
 * @param int $x2 x-coordinate for second point.
 * @param int $y2 y-coordinate for second point.
 * @param int $color The line color. A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imageline(GdImage $image, int $x1, int $y1, int $x2, int $y2, int $color): bool {}

/**
 * Load a new font
 * @param string $filename The font file format is currently binary and architecture dependent. This means you should generate the font files on the same type of CPU as the machine you are running PHP on. Font file format byte position C data type description byte 0-3 int number of characters in the ...
 * @return int|false The font identifier which is always bigger than 5 to avoid conflicts with built-in fonts or false on errors.
 */
function imageloadfont(string $filename): GdFont|false {}

/**
 * Draws a polygon
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int[] $points An array containing the polygon's vertices, e.g.: points[0] = x0 points[1] = y0 points[2] = x1 points[3] = y1
 * @param int $num_points_or_color Total number of points (vertices).
 * @param int|null $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagepolygon(
    GdImage $image,
    array $points,
    int $num_points_or_color,
    ?int $color = null
): bool {}

/**
 * Draw a rectangle
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x1 Upper left x coordinate.
 * @param int $y1 Upper left y coordinate 0, 0 is the top left corner of the image.
 * @param int $x2 Bottom right x coordinate.
 * @param int $y2 Bottom right y coordinate.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagerectangle(GdImage $image, int $x1, int $y1, int $x2, int $y2, int $color): bool {}

/**
 * Set a single pixel
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x x-coordinate.
 * @param int $y y-coordinate.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagesetpixel(GdImage $image, int $x, int $y, int $color): bool {}

/**
 * Draw a string horizontally
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or (since 8.1) GdFont instance
 * @param int $x x-coordinate of the upper left corner.
 * @param int $y y-coordinate of the upper left corner.
 * @param string $string The string to be written.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagestring(
    GdImage $image,
    GdFont|int $font,
    int $x,
    int $y,
    string $string,
    int $color
): bool {}

/**
 * Draw a string vertically
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $font Can be 1, 2, 3, 4, 5 for built-in fonts in latin2 encoding (where higher numbers corresponding to larger fonts) or GdFont instance, returned by imageloadfont.
 * @param int $x x-coordinate of the upper left corner.
 * @param int $y y-coordinate of the upper left corner.
 * @param string $string The string to be written.
 * @param int $color A color identifier created with imagecolorallocate.
 * @return bool true on success or false on failure.
 */
function imagestringup(
    GdImage $image,
    GdFont|int $font,
    int $x,
    int $y,
    string $string,
    int $color
): bool {}

/**
 * Get image width
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @return int|false Return the width of the image or false on errors.
 */
function imagesx(GdImage $image): int {}

/**
 * Get image height
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @return int|false Return the height of the image or false on errors.
 */
function imagesy(GdImage $image): int {}

/**
 * Draw a dashed line
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $x1 Upper left x coordinate.
 * @param int $y1 Upper left y coordinate 0, 0 is the top left corner of the image.
 * @param int $x2 Bottom right x coordinate.
 * @param int $y2 Bottom right y coordinate.
 * @param int $color The fill color. A color identifier created with imagecolorallocate.
 * @return bool TRUE on success or FALSE on failure.
 */
function imagedashedline(GdImage $image, int $x1, int $y1, int $x2, int $y2, int $color): bool {}

/**
 * Give the bounding box of a text using TrueType fonts
 * @param float $size The font size. Depending on your version of GD, this should be specified as the pixel size (GD1) or point size (GD2).
 * @param float $angle Angle in degrees in which text will be measured.
 * @param string $font_filename The name of the TrueType font file (can be a URL). Depending on which version of the GD library that PHP is using, it may attempt to search for files that do not begin with a leading '/' by appending '.ttf' to the filename and searching along a library-defined font path.
 * @param string $string The string to be measured.
 * @param array $options [optional]
 * @return array|false imagettfbbox returns an array with 8 elements representing four points making the bounding box of the text on success and false on error. key contents 0 lower left corner, X position 1 lower left corner, Y position 2 lower right corner, X position 3 lower right corner, Y ...
 */
function imagettfbbox(float $size, float $angle, string $font_filename, string $string, array $options = []): array|false {}

/**
 * Write text to the image using TrueType fonts
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param float $size The font size. Depending on your version of GD, this should be specified as the pixel size (GD1) or point size (GD2).
 * @param float $angle The angle in degrees, with 0 degrees being left-to-right reading text. Higher values represent a counter-clockwise rotation. For example, a value of 90 would result in bottom-to-top reading text.
 * @param int $x The coordinates given by x and y will define the basepoint of the first character (roughly the lower-left corner of the character). This is different from the imagestring, where x and y define the upper-left corner of the first character. For example, "top left" is 0, 0.
 * @param int $y The y-ordinate. This sets the position of the fonts baseline, not the very bottom of the character.
 * @param int $color The color index. Using the negative of a color index has the effect of turning off antialiasing. See imagecolorallocate.
 * @param string $font_filename The path to the TrueType font you wish to use. Depending on which version of the GD library PHP is using, when font_filename does not begin with a leading / then .ttf will be appended to the filename and the library will attempt to search for that filename along a ...
 * @param string $text The text string in UTF-8 encoding. May include decimal numeric character references (of the form: &#8364;) to access characters in a font beyond position 127. The hexadecimal format (like &#xA9;) is supported. Strings in UTF-8 encoding can be passed directly. Named entities, ...
 * @param array $options [optional]
 * @return array|false an array with 8 elements representing four points making the bounding box of the text. The order of the points is lower left, lower right, upper right, upper left. The points are relative to the text regardless of the angle, so "upper left" means in the top left-hand corner when ...
 */
function imagettftext(GdImage $image, float $size, float $angle, int $x, int $y, int $color, string $font_filename, string $text, array $options = []): array|false {}

/**
 * Give the bounding box of a text using fonts via freetype2
 * @param float $size The font size. Depending on your version of GD, this should be specified as the pixel size (GD1) or point size (GD2).
 * @param float $angle Angle in degrees in which text will be measured.
 * @param string $font_filename The name of the TrueType font file (can be a URL). Depending on which version of the GD library that PHP is using, it may attempt to search for files that do not begin with a leading '/' by appending '.ttf' to the filename and searching along a library-defined font path.
 * @param string $string The string to be measured.
 * @param array $options [optional] Possible array indexes for extrainfo Key Type Meaning linespacing float Defines drawing linespacing
 * @return array|false imageftbbox returns an array with 8 elements representing four points making the bounding box of the text: 0 lower left corner, X position 1 lower left corner, Y position 2 lower right corner, X position 3 lower right corner, Y position 4 upper right corner, X position 5 upper ...
 */
function imageftbbox(float $size, float $angle, string $font_filename, string $string, array $options = []): array|false {}

/**
 * Write text to the image using fonts using FreeType 2
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param float $size The font size to use in points.
 * @param float $angle The angle in degrees, with 0 degrees being left-to-right reading text. Higher values represent a counter-clockwise rotation. For example, a value of 90 would result in bottom-to-top reading text.
 * @param int $x The coordinates given by x and y will define the basepoint of the first character (roughly the lower-left corner of the character). This is different from the imagestring, where x and y define the upper-left corner of the first character. For example, "top left" is 0, 0.
 * @param int $y The y-ordinate. This sets the position of the fonts baseline, not the very bottom of the character.
 * @param int $color The index of the desired color for the text, see imagecolorexact.
 * @param string $font_filename The path to the TrueType font you wish to use. Depending on which version of the GD library PHP is using, when font_filename does not begin with a leading / then .ttf will be appended to the filename and the library will attempt to search for that filename along a ...
 * @param string $text Text to be inserted into image.
 * @param array $options [optional] Possible array indexes for extrainfo Key Type Meaning linespacing float Defines drawing linespacing
 * @return array|false This function returns an array defining the four points of the box, starting in the lower left and moving counter-clockwise: 0 lower left x-coordinate 1 lower left y-coordinate 2 lower right x-coordinate 3 lower right y-coordinate 4 upper right x-coordinate 5 upper right ...
 */
function imagefttext(GdImage $image, float $size, float $angle, int $x, int $y, int $color, string $font_filename, string $text, array $options = []): array|false {}

/**
 * Load a PostScript Type 1 font from file
 * @param string $filename Path to the Postscript font file.
 * @return resource|GdImage|false In the case everything went right, a valid font index will be returned and can be used for further purposes. Otherwise the function returns false.
 * @removed 7.0 This function was REMOVED in PHP 7.0.0.
 */
function imagepsloadfont($filename) {}

/**
 * Free memory used by a PostScript Type 1 font
 * @param resource|GdImage $font_index A font resource, returned by imagepsloadfont.
 * @return bool true on success or false on failure.
 * @removed 7.0
 */
function imagepsfreefont($font_index) {}

/**
 * Change the character encoding vector of a font
 * @param resource|GdImage $font_index A font resource, returned by imagepsloadfont.
 * @param string $encodingfile The exact format of this file is described in T1libs documentation. T1lib comes with two ready-to-use files, IsoLatin1.enc and IsoLatin2.enc.
 * @return bool true on success or false on failure.
 * @removed 7.0
 */
function imagepsencodefont($font_index, $encodingfile) {}

/**
 * Extend or condense a font
 * @param resource|GdImage $font_index A font resource, returned by imagepsloadfont.
 * @param float $extend Extension value, must be greater than 0.
 * @return bool true on success or false on failure.
 * @removed 7.0
 */
function imagepsextendfont($font_index, $extend) {}

/**
 * Slant a font
 * @param resource|GdImage $font_index A font resource, returned by imagepsloadfont.
 * @param float $slant Slant level.
 * @return bool true on success or false on failure.
 * @removed 7.0 This function was REMOVED in PHP 7.0.0.
 */
function imagepsslantfont($font_index, $slant) {}

/**
 * Draws a text over an image using PostScript Type1 fonts
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param string $text The text to be written.
 * @param resource|GdImage $font_index A font resource, returned by imagepsloadfont.
 * @param int $size size is expressed in pixels.
 * @param int $foreground The color in which the text will be painted.
 * @param int $background The color to which the text will try to fade in with antialiasing. No pixels with the color background are actually painted, so the background image does not need to be of solid color.
 * @param int $x x-coordinate for the lower-left corner of the first character.
 * @param int $y y-coordinate for the lower-left corner of the first character.
 * @param int $space [optional] Allows you to change the default value of a space in a font. This amount is added to the normal value and can also be negative. Expressed in character space units, where 1 unit is 1/1000th of an em-square.
 * @param int $tightness [optional] tightness allows you to control the amount of white space between characters. This amount is added to the normal character width and can also be negative. Expressed in character space units, where 1 unit is 1/1000th of an em-square.
 * @param float $angle [optional] angle is in degrees.
 * @param int $antialias_steps [optional] Allows you to control the number of colours used for antialiasing text. Allowed values are 4 and 16. The higher value is recommended for text sizes lower than 20, where the effect in text quality is quite visible. With bigger sizes, use 4. It's less ...
 * @return array|false This function returns an array containing the following elements: 0 lower left x-coordinate 1 lower left y-coordinate 2 upper right x-coordinate 3 upper right y-coordinate Returns false on error.
 * @removed 7.0 This function was REMOVED in PHP 7.0.0.
 */
function imagepstext($image, $text, $font_index, $size, $foreground, $background, $x, $y, $space = null, $tightness = null, $angle = null, $antialias_steps = null) {}

/**
 * Give the bounding box of a text rectangle using PostScript Type1 fonts
 * @param string $text The text to be written.
 * @param resource|GdImage $font
 * @param int $size size is expressed in pixels.
 * @return array|false an array containing the following elements: 0 left x-coordinate 1 upper y-coordinate 2 right x-coordinate 3 lower y-coordinate Returns false on error.
 * @removed 7.0
 */
function imagepsbbox($text, $font, $size) {}

/**
 * Return the image types supported by this PHP build
 * @return int a bit-field corresponding to the image formats supported by the version of GD linked into PHP. The following bits are returned, IMG_BMP | IMG_GIF | IMG_JPG | IMG_PNG | IMG_WBMP | IMG_XPM | IMG_WEBP
 */
function imagetypes(): int {}

/**
 * Convert JPEG image file to WBMP image file
 * @param string $jpegname Path to JPEG file.
 * @param string $wbmpname Path to destination WBMP file.
 * @param int $dest_height Destination image height.
 * @param int $dest_width Destination image width.
 * @param int $threshold Threshold value, between 0 and 8 (inclusive).
 * @return bool true on success or false on failure.
 * @removed 8.0
 * @see imagecreatefromjpeg()
 * @deprecated Use imagecreatefromjpeg() and imagewbmp() instead
 */
function jpeg2wbmp($jpegname, $wbmpname, $dest_height, $dest_width, $threshold) {}

/**
 * Convert PNG image file to WBMP image file
 * @param string $pngname Path to PNG file.
 * @param string $wbmpname Path to destination WBMP file.
 * @param int $dest_height Destination image height.
 * @param int $dest_width Destination image width.
 * @param int $threshold Threshold value, between 0 and 8 (inclusive).
 * @return bool true on success or false on failure.
 * @removed 8.0
 * @see imagecreatefrompng()
 * @see imagewbmp()
 * @deprecated
 */
function png2wbmp($pngname, $wbmpname, $dest_height, $dest_width, $threshold) {}

/**
 * Output image to browser or file
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string $filename [optional] Path to the saved file. If not given, the raw image stream will be outputted directly.
 * @param int $threshold [optional] Threshold value, between 0 and 255 (inclusive).
 * @return bool true on success or false on failure.
 * @removed 8.0
 * @see imagewbmp()
 * @deprecated
 */
function image2wbmp($image, $filename = null, $threshold = null) {}

/**
 * Set the alpha blending flag to use the bundled libgd layering effects
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $effect One of the following constants: IMG_EFFECT_REPLACE Use pixel replacement (equivalent of passing true to imagealphablending)
 * @return bool true on success or false on failure.
 */
function imagelayereffect(GdImage $image, int $effect): bool {}

/**
 * Makes the colors of the palette version of an image more closely match the true color version
 * @param resource|GdImage $image1 A truecolor image link resource.
 * @param resource|GdImage $image2 A palette image link resource pointing to an image that has the same size as image1.
 * @return bool true on success or false on failure.
 */
function imagecolormatch(GdImage $image1, GdImage $image2): bool {}

/**
 * Output XBM image to browser or file
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param string|null $filename The path to save the file to. If not set or null, the raw image stream will be outputted directly.
 * @param int|null $foreground_color [optional] You can set the foreground color with this parameter by setting an identifier obtained from imagecolorallocate. The default foreground color is black.
 * @return bool true on success or false on failure.
 */
function imagexbm(GdImage $image, ?string $filename, ?int $foreground_color = null): bool {}

/**
 * Applies a filter to an image
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param int $filter filtertype can be one of the following: IMG_FILTER_NEGATE: Reverses all colors of the image.
 * @param int ...$args IMG_FILTER_BRIGHTNESS: Brightness level. IMG_FILTER_CONTRAST: Contrast level. IMG_FILTER_COLORIZE: Value of red component. IMG_FILTER_SMOOTH: Smoothness level. IMG_FILTER_PIXELATE: Block size in pixels. IMG_FILTER_SCATTER: Effect subtraction level. This must not be higher or ...
 * @return bool true on success or false on failure.
 * @throws \ValueError Throws a ValueError if sub or plus would cause over-/underflow with the IMG_FILTER_SCATTER filter.
 */
function imagefilter(
    GdImage $image,
    int $filter,
    ...$args
): bool {}

/**
 * Apply a 3x3 convolution matrix, using coefficient and offset
 * @param resource|GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @param array $matrix A 3x3 matrix: an array of three arrays of three floats.
 * @param float $divisor The divisor of the result of the convolution, used for normalization.
 * @param float $offset Color offset.
 * @return bool true on success or false on failure.
 */
function imageconvolution(GdImage $image, array $matrix, float $divisor, float $offset): bool {}

/**
 * Get or set the resolution of the image
 *
 * imageresolution allows to set and get the resolution of an image in DPI (dots per inch). If the
 * optional parameters are null, the current resolution is returned as an indexed array. If only
 * resolution_x is not null, the horizontal and vertical resolution are set to this value. If none
 * of the optional parameters are null, the horizontal and vertical resolution are set to these
 * values, respectively.
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int|null $resolution_x The horizontal resolution in DPI.
 * @param int|null $resolution_y The vertical resolution in DPI.
 * @return array|bool When used as getter (that is without the optional parameters), it returns TRUE on success, or FALSE on failure. When used as setter (that is with one or both optional parameters given), it returns an indexed array of the horizontal and vertical resolution on success, or FALSE on ...
 * @since 7.2
 */
function imageresolution(GdImage $image, ?int $resolution_x = null, ?int $resolution_y = null): array|bool {}

/**
 * imagesetclip() sets the current clipping rectangle, i.e. the area beyond which no pixels will be drawn.
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int $x1 The x-coordinate of the upper left corner.
 * @param int $y1 The y-coordinate of the upper left corner.
 * @param int $x2 The x-coordinate of the lower right corner.
 * @param int $y2 The y-coordinate of the lower right corner.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @see imagegetclip()
 * @since 7.2
 */
function imagesetclip(GdImage $image, int $x1, int $y1, int $x2, int $y2): bool {}

/**
 * imagegetclip() retrieves the current clipping rectangle, i.e. the area beyond which no pixels will be drawn.
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor()
 * @return array|false an indexed array with the coordinates of the clipping rectangle which has the following entries: x-coordinate of the upper left corner y-coordinate of the upper left corner x-coordinate of the lower right corner y-coordinate of the lower right corner Returns FALSE on error.
 * @see imagesetclip()
 * @since 7.2
 */
function imagegetclip(GdImage $image): array {}

/**
 * imageopenpolygon() draws an open polygon on the given image. Contrary to imagepolygon(), no line is drawn between the last and the first point.
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int[] $points An array containing the polygon's vertices, e.g.: points[0]	= x0 points[1]	= y0 points[2]	= x1 points[3]	= y1
 * @param int $num_points_or_color Total number of points (vertices).
 * @param int|null $color A color identifier created with imagecolorallocate().
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 7.2
 * @see imageplygon()
 */
function imageopenpolygon(
    GdImage $image,
    array $points,
    int $num_points_or_color,
    ?int $color = null
): bool {}

/**
 * imagecreatefrombmp() returns an image identifier representing the image obtained from the given filename.
 * TIP A URL can be used as a filename with this function if the fopen wrappers have been enabled. See fopen() for more details on how to specify the filename. See the Supported Protocols and Wrappers for links to information about what abilities the various wrappers have, notes on their usage, and information on any predefined variables they may provide.
 * @param string $filename Path to the BMP image.
 * @return resource|GdImage|false Returns an image resource identifier on success, FALSE on errors.
 * @since 7.2
 */
function imagecreatefrombmp(string $filename): GdImage|false {}

/**
 * Outputs or saves a BMP version of the given image.
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param mixed $file The path or an open stream resource (which is automatically being closed after this function returns) to save the file to. If not set or NULL, the raw image stream will be outputted directly. Note: NULL is invalid if the compressed arguments is not used.
 * @param bool $compressed Whether the BMP should be compressed with run-length encoding (RLE), or not.
 * @return bool Returns TRUE on success or FALSE on failure. Caution However, if libgd fails to output the image, this function returns TRUE.
 * @since 7.2
 */
function imagebmp(GdImage $image, $file = null, bool $compressed = true): bool {}

/**
 * Create a new image from file or URL
 *
 * imagecreatefromtga returns an image object representing the image obtained from the given
 * filename.
 * @param string $filename Path to the Truevision TGA image.
 * @return resource|GdImage|false Returns an image object on success, false on errors.
 */
function imagecreatefromtga(string $filename): GdImage|false {}

/**
 * Captures the whole screen
 *
 * https://www.php.net/manual/en/function.imagegrabscreen.php
 * @return resource|GdImage|false Returns an image object on success, false on failure.
 */
function imagegrabscreen() {}

/**
 * Captures a window
 * @param int $handle The HWND window ID.
 * @param int|null $client_area Include the client area of the application window.
 * @return resource|GdImage|false Returns an image object on success, false on failure.
 */
function imagegrabwindow($handle, $client_area = null) {}

/**
 * Gets the currently set interpolation method of the image.
 * @param GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor.
 * @return int Returns the interpolation method.
 */
function imagegetinterpolation(GdImage $image): int {}

/**
 * Outputs or saves a AVIF Raster image from the given image
 * @param GdImage $image A GdImage object, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param resource|string|null $file The path or an open stream resource (which is automatically closed after this function returns) to save the file to. If not set or null, the raw image stream will be output directly.
 * @param int $quality quality is optional, and ranges from 0 (worst quality, smaller file) to 100 (best quality, larger file). If -1 is provided, the default value 30 is used.
 * @param int $speed speed is optional, and ranges from 0 (slow, smaller file) to 10 (fast, larger file). If -1 is provided, the default value 6 is used.
 * @return bool Returns true on success or false on failure. However, if libgd fails to output the image, this function returns true.
 * @since 8.1
 * @throws \ValueError Throws a ValueError if quality or speed is invalid.
 */
function imageavif(GdImage $image, string|null $file = null, int $quality = -1, int $speed = -1): bool {}

/**
 * Return an image containing the affine tramsformed src image, using an optional clipping area
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param array $affine Array with keys 0 to 5.
 * @param array|null $clip [optional] Array with keys "x", "y", "width" and "height".
 * @return resource|GdImage|false Return affined image resource on success or FALSE on failure.
 */
function imageaffine(GdImage $image, array $affine, ?array $clip = null): GdImage|false {}

/**
 * Concat two matrices (as in doing many ops in one go)
 * @param array $matrix1 Array with keys 0 to 5.
 * @param array $matrix2 Array with keys 0 to 5.
 * @return float[]|false Array with keys 0 to 5 and float values or FALSE on failure.
 * @since 5.5
 */
function imageaffinematrixconcat(array $matrix1, array $matrix2): array|false {}

/**
 * Return an image containing the affine tramsformed src image, using an optional clipping area
 * @param int $type  One of IMG_AFFINE_* constants.
 * @param mixed $options If type is IMG_AFFINE_TRANSLATE or IMG_AFFINE_SCALE, options has to be an array with keys x and y, both having float values. If type is IMG_AFFINE_ROTATE, IMG_AFFINE_SHEAR_HORIZONTAL or IMG_AFFINE_SHEAR_VERTICAL, options has to be a float specifying the angle.
 * @return float[]|false Array with keys 0 to 5 and float values or FALSE on failure.
 * @since 5.5
 */
function imageaffinematrixget(
    int $type,
    $options
): array|false {}

/**
 * Crop an image using the given coordinates and size, x, y, width and height
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param array $rectangle Array with keys "x", "y", "width" and "height".
 * @return resource|GdImage|false Return cropped image resource on success or FALSE on failure.
 * @since 5.5
 */
function imagecrop(GdImage $image, array $rectangle): GdImage|false {}

/**
 * Crop an image automatically using one of the available modes
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int $mode [optional] One of IMG_CROP_* constants.
 * @param float $threshold [optional] Used IMG_CROP_THRESHOLD mode.
 * @param int $color [optional] Used in IMG_CROP_THRESHOLD mode.
 * @return resource|GdImage|false Return cropped image resource on success or FALSE on failure.
 * @since 5.5
 */
function imagecropauto(GdImage $image, int $mode = IMG_CROP_DEFAULT, float $threshold = .5, int $color = -1): GdImage|false {}

/**
 * Flips an image using a given mode
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int $mode Flip mode, this can be one of the IMG_FLIP_* constants: Constant Meaning IMG_FLIP_HORIZONTAL Flips the image horizontally. IMG_FLIP_VERTICAL Flips the image vertically. IMG_FLIP_BOTH Flips the image both horizontally and vertically.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function imageflip(GdImage $image, int $mode): bool {}

/**
 * Converts a palette based image to true color
 * @param resource|GdImage $image An image resource, returnd by one of the image creation functions, such as imagecreatetruecolor().
 * @return bool Returns TRUE if the convertion was complete, or if the source image already is a true color image, otherwise FALSE is returned.
 * @since 5.5
 */
function imagepalettetotruecolor(GdImage $image): bool {}

/**
 * Scale an image using the given new width and height
 *
 * imagescale scales an image using the given interpolation algorithm.
 * @param resource|GdImage $image An image resource, returnd by one of the image creation functions, such as imagecreatetruecolor().
 * @param int $width The width to scale the image to.
 * @param int $height [optional]
 * @param int $mode [optional] One of IMG_NEAREST_NEIGHBOUR, IMG_BILINEAR_FIXED, IMG_BICUBIC, IMG_BICUBIC_FIXED or anything else (will use two pass).
 * @return resource|GdImage|false Return scaled image resource on success or FALSE on failure.
 * @since 5.5 Scale an image using the given new width and height
 * @throws \ValueError Throws a ValueError if width or height would cause over-/underflow. Throws a ValueError if mode is invalid.
 */
function imagescale(GdImage $image, int $width, int $height = -1, int $mode = IMG_BILINEAR_FIXED): GdImage|false {}

/**
 * Set the interpolation method
 * @param resource|GdImage $image An image resource, returned by one of the image creation functions, such as imagecreatetruecolor().
 * @param int $method The interpolation method, which can be one of the following: IMG_BELL: Bell filter. IMG_BESSEL: Bessel filter. IMG_BICUBIC: Bicubic interpolation. IMG_BICUBIC_FIXED: Fixed point implementation of the bicubic interpolation. IMG_BILINEAR_FIXED: Fixed point implementation of the  ...
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function imagesetinterpolation(GdImage $image, int $method = IMG_BILINEAR_FIXED): bool {}
