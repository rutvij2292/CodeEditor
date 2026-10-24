<?php

/**
 * Reads the EXIF headers from JPEG or TIFF
 * @param string $file The location of the image file. This cannot be an URL. Since 7.2.0 this can either be a path to the file (stream wrappers are also supported as usual) or a stream resource.
 * @param string|null $required_sections [optional] Is a comma separated list of sections that need to be present in file to produce a result array. If none of the requested sections could be found the return value is FALSE. FILE FileName, FileSize, FileDateTime, SectionsFound COMPUTED html, Width, ...
 * @param bool $as_arrays [optional] Specifies whether or not each section becomes an array. The sections COMPUTED, THUMBNAIL, and COMMENT always become arrays as they may contain values whose names conflict with other sections.
 * @param bool $read_thumbnail [optional] When set to TRUE the thumbnail itself is read. Otherwise, only the tagged data is read.
 * @return array|false It returns an associative array where the array indexes are the header names and the array values are the values associated with those headers. If no data can be returned, exif_read_data will return FALSE.
 */
function exif_read_data($file, ?string $required_sections = null, bool $as_arrays = false, bool $read_thumbnail = false): array|false {}

/**
 * Alias of exif_read_data
 * @param $filename
 * @param $sections [optional]
 * @param $arrays [optional]
 * @param $thumbnail [optional]
 * @removed 8.0
 * @deprecated
 */
function read_exif_data($filename, $sections = null, $arrays = false, $thumbnail = false) {}

/**
 * Get the header name for an index
 * @param int $index The Tag ID for which a Tag Name will be looked up.
 * @return string|false the header name, or FALSE if index is not a defined EXIF tag id.
 */
function exif_tagname(int $index): string|false {}

/**
 * Retrieve the embedded thumbnail of a TIFF or JPEG image
 * @param string|resource $file The location of the image file. This cannot be an URL. Since 7.2.0 this can either be a path to the file (stream wrappers are also supported as usual) or a stream resource.
 * @param int &$width [optional] The return width of the returned thumbnail.
 * @param int &$height [optional] The returned height of the returned thumbnail.
 * @param int &$image_type [optional] The returned image type of the returned thumbnail. This is either TIFF or JPEG.
 * @return string|false the embedded thumbnail, or FALSE if the image contains no thumbnail.
 */
function exif_thumbnail($file, &$width = null, &$height = null, &$image_type = null): string|false {}

/**
 * Determine the type of an image
 * @param string $filename The image being checked.
 * @return int|false When a correct signature is found, the appropriate constant value will be returned otherwise the return value is FALSE. The return value is the same value that getimagesize returns in index 2 but exif_imagetype is much faster. exif_imagetype will emit an E_NOTICE and return FALSE ...
 */
function exif_imagetype(string $filename): int|false {}
