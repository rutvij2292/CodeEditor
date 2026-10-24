<?php

/**
 * Used as a return value by imagetypes()
 */
const IMG_GIF = 1;

/**
 * Used as a return value by imagetypes()
 */
const IMG_JPG = 2;

/**
 * Used as a return value by imagetypes()
 *
 * This constant has the same value as IMG_JPG
 */
const IMG_JPEG = 2;

/**
 * Used as a return value by imagetypes()
 */
const IMG_PNG = 4;

/**
 * Used as a return value by imagetypes()
 */
const IMG_WBMP = 8;

/**
 * Used as a return value by imagetypes()
 */
const IMG_XPM = 16;

/**
 * Used as a return value by imagetypes()
 * @since 5.6
 * @since 7.0
 */
const IMG_WEBP = 32;

/**
 * Used as a return value by imagetypes()
 * @since 7.2
 */
const IMG_BMP = 64;

/**
 * Special color option which can be used instead of color allocated with
 * imagecolorallocate() or imagecolorallocatealpha()
 */
const IMG_COLOR_TILED = -5;

/**
 * Special color option which can be used instead of color allocated with
 * imagecolorallocate() or imagecolorallocatealpha()
 */
const IMG_COLOR_STYLED = -2;

/**
 * Special color option which can be used instead of color allocated with
 * imagecolorallocate() or imagecolorallocatealpha()
 */
const IMG_COLOR_BRUSHED = -3;

/**
 * Special color option which can be used instead of color allocated with
 * imagecolorallocate() or imagecolorallocatealpha()
 */
const IMG_COLOR_STYLEDBRUSHED = -4;

/**
 * Special color option which can be used instead of color allocated with
 * imagecolorallocate() or imagecolorallocatealpha()
 */
const IMG_COLOR_TRANSPARENT = -6;

/**
 * A style constant used by the imagefilledarc() function.
 *
 * This constant has the same value as IMG_ARC_PIE
 */
const IMG_ARC_ROUNDED = 0;

/**
 * A style constant used by the imagefilledarc() function.
 */
const IMG_ARC_PIE = 0;

/**
 * A style constant used by the imagefilledarc() function.
 */
const IMG_ARC_CHORD = 1;

/**
 * A style constant used by the imagefilledarc() function.
 */
const IMG_ARC_NOFILL = 2;

/**
 * A style constant used by the imagefilledarc() function.
 */
const IMG_ARC_EDGED = 4;

/**
 * A type constant used by the imagegd2() function.
 */
const IMG_GD2_RAW = 1;

/**
 * A type constant used by the imagegd2() function.
 */
const IMG_GD2_COMPRESSED = 2;

/**
 * Alpha blending effect used by the imagelayereffect() function.
 */
const IMG_EFFECT_REPLACE = 0;

/**
 * Alpha blending effect used by the imagelayereffect() function.
 */
const IMG_EFFECT_ALPHABLEND = 1;

/**
 * Alpha blending effect used by the imagelayereffect() function.
 */
const IMG_EFFECT_NORMAL = 2;

/**
 * Alpha blending effect used by the imagelayereffect() function.
 */
const IMG_EFFECT_OVERLAY = 3;

/**
 * Alpha blending effect used by the imagelayereffect() function.
 * @since 7.2
 */
const IMG_EFFECT_MULTIPLY = 4;

/**
 * When the bundled version of GD is used this is 1 otherwise
 * it's set to 0.
 */
const GD_BUNDLED = 1;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_NEGATE = 0;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_GRAYSCALE = 1;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_BRIGHTNESS = 2;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_CONTRAST = 3;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_COLORIZE = 4;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_EDGEDETECT = 5;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_GAUSSIAN_BLUR = 7;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_SELECTIVE_BLUR = 8;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_EMBOSS = 6;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_MEAN_REMOVAL = 9;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_SMOOTH = 10;

/**
 * Special GD filter used by the imagefilter() function.
 */
const IMG_FILTER_PIXELATE = 11;

/**
 * Special GD filter used by the imagefilter() function.
 * @since 7.4
 */
const IMG_FILTER_SCATTER = 12;

/**
 * The GD version PHP was compiled against.
 * @since 5.2
 */
const GD_VERSION = "2.4.0";

/**
 * The GD major version PHP was compiled against.
 * @since 5.2
 */
const GD_MAJOR_VERSION = 2;

/**
 * The GD minor version PHP was compiled against.
 * @since 5.2
 */
const GD_MINOR_VERSION = 4;

/**
 * The GD release version PHP was compiled against.
 * @since 5.2
 */
const GD_RELEASE_VERSION = 0;

/**
 * The GD "extra" version (beta/rc..) PHP was compiled against.
 * @since 5.2
 */
const GD_EXTRA_VERSION = "";

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_NO_FILTER = 0;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_FILTER_NONE = 8;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_FILTER_SUB = 16;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_FILTER_UP = 32;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_FILTER_AVG = 64;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_FILTER_PAETH = 128;

/**
 * A special PNG filter, used by the imagepng() function.
 */
const PNG_ALL_FILTERS = 248;

/**
 * An affine transformation type constant used by the imageaffinematrixget() function.
 * @since 5.5
 */
const IMG_AFFINE_TRANSLATE = 0;

/**
 * An affine transformation type constant used by the imageaffinematrixget() function.
 * @since 5.5
 */
const IMG_AFFINE_SCALE = 1;

/**
 * An affine transformation type constant used by the imageaffinematrixget() function.
 * @since 5.5
 */
const IMG_AFFINE_ROTATE = 2;

/**
 * An affine transformation type constant used by the imageaffinematrixget() function.
 * @since 5.5
 */
const IMG_AFFINE_SHEAR_HORIZONTAL = 3;

/**
 * An affine transformation type constant used by the imageaffinematrixget() function.
 * @since 5.5
 */
const IMG_AFFINE_SHEAR_VERTICAL = 4;

/**
 * Same as IMG_CROP_TRANSPARENT. Before PHP 7.4.0, the bundled libgd fell back to
 * IMG_CROP_SIDES, if the image had no transparent color.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_DEFAULT = 0;

/**
 * Crops out a transparent background.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_TRANSPARENT = 1;

/**
 * Crops out a black background.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_BLACK = 2;

/**
 * Crops out a white background.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_WHITE = 3;

/**
 * Uses the 4 corners of the image to attempt to detect the background to crop.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_SIDES = 4;

/**
 * Crops an image using the given threshold and color.
 * Used together with imagecropauto().
 * @since 5.5
 */
const IMG_CROP_THRESHOLD = 5;

/**
 * Used together with imageflip()
 * @since 5.5
 */
const IMG_FLIP_BOTH = 3;

/**
 * Used together with imageflip()
 * @since 5.5
 */
const IMG_FLIP_HORIZONTAL = 1;

/**
 * Used together with imageflip()
 * @since 5.5
 */
const IMG_FLIP_VERTICAL = 2;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BELL = 1;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BESSEL = 2;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BICUBIC = 4;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BICUBIC_FIXED = 5;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BILINEAR_FIXED = 3;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BLACKMAN = 6;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BOX = 7;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_BSPLINE = 8;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_CATMULLROM = 9;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_GAUSSIAN = 10;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_GENERALIZED_CUBIC = 11;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_HERMITE = 12;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_HAMMING = 13;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_HANNING = 14;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_MITCHELL = 15;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_POWER = 17;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_QUADRATIC = 18;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_SINC = 19;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_NEAREST_NEIGHBOUR = 16;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_WEIGHTED4 = 21;

/**
 * Used together with imagesetinterpolation().
 * @since 5.5
 */
const IMG_TRIANGLE = 20;

const IMG_TGA = 128;

/**
 * @since 8.1
 */
const IMG_AVIF = 256;

/**
 * @since 8.1
 */
const IMG_WEBP_LOSSLESS = 101;
