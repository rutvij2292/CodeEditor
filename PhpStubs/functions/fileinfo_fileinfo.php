<?php

/**
 * Create a new fileinfo resource
 * @param int $flags One or disjunction of more Fileinfo constants.
 * @param string|null $magic_database [optional] Name of a magic database file, usually something like /path/to/magic.mime. If not specified, the MAGIC environment variable is used. If this variable is not set either, /usr/share/misc/magic is used by default. A .mime and/or .mgc suffix is added if ...
 * @return resource|false a magic database resource on success or FALSE on failure.
 */
function finfo_open(int $flags = 0, ?string $magic_database = null): finfo|false {}

/**
 * Close fileinfo resource
 * @param resource $finfo Fileinfo resource returned by finfo_open.
 * @return bool TRUE on success or FALSE on failure.
 */
function finfo_close(finfo $finfo): bool {}

/**
 * Set libmagic configuration options
 * @param resource $finfo Fileinfo resource returned by finfo_open.
 * @param int $flags One or disjunction of more Fileinfo constants.
 * @return bool TRUE on success or FALSE on failure.
 */
function finfo_set_flags(finfo $finfo, int $flags): bool {}

/**
 * Return information about a file
 * @param resource $finfo Fileinfo resource returned by finfo_open.
 * @param string $filename Name of a file to be checked.
 * @param int $flags One or disjunction of more Fileinfo constants.
 * @param resource $context [optional] For a description of contexts, refer to .
 * @return string|false a textual description of the contents of the filename argument, or FALSE if an error occurred.
 */
function finfo_file(finfo $finfo, string $filename, int $flags = 0, $context = null): string|false {}

/**
 * Return information about a string buffer
 * @param resource $finfo Fileinfo resource returned by finfo_open.
 * @param string $string Content of a file to be checked.
 * @param int $flags [optional] One or disjunction of more Fileinfo constants.
 * @param resource $context [optional]
 * @return string|false a textual description of the string argument, or FALSE if an error occurred.
 */
function finfo_buffer(finfo $finfo, string $string, int $flags = FILEINFO_NONE, $context = null): string|false {}

/**
 * Detect MIME Content-type for a file
 * @param resource|string $filename Path to the tested file.
 * @return string|false the content type in MIME format, like text/plain or application/octet-stream.
 */
function mime_content_type($filename): string|false {}
