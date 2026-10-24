<?php

/**
 * Open a ZIP file archive
 * @param string $filename The file name of the ZIP archive to open.
 * @return resource|int|false a resource handle for later use with zip_read and zip_close or returns the number of error if filename does not exist or in case of other error.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_open(string $filename) {}

/**
 * Close a ZIP file archive
 * @param resource $zip A ZIP file previously opened with zip_open.
 * @return void No value is returned.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_close($zip): void {}

/**
 * Read next entry in a ZIP file archive
 * @param resource $zip A ZIP file previously opened with zip_open.
 * @return resource|false a directory entry resource for later use with the zip_entry_... functions, or FALSE if there are no more entries to read, or an error code if an error occurred.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_read($zip) {}

/**
 * Open a directory entry for reading
 * @param resource $zip_dp A valid resource handle returned by zip_open.
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @param string $mode [optional] Any of the modes specified in the documentation of fopen. Currently, mode is ignored and is always "rb". This is due to the fact that zip support in PHP is read only access.
 * @return bool TRUE on success or FALSE on failure. Unlike fopen and other similar functions, the return value of zip_entry_open only indicates the result of the operation and is not needed for reading or closing the directory entry.
 * @deprecated This function is deprecated in favor of the Object API
 */
function zip_entry_open($zip_dp, $zip_entry, string $mode = 'rb'): bool {}

/**
 * Close a directory entry
 * @param resource $zip_entry A directory entry previously opened zip_entry_open.
 * @return bool TRUE on success or FALSE on failure.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_close($zip_entry): bool {}

/**
 * Read from an open directory entry
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @param int $len [optional] The number of bytes to return. This should be the uncompressed length you wish to read.
 * @return string|false the data read, empty string on end of a file, or FALSE on error.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_read($zip_entry, int $len = 1024): string|false {}

/**
 * Retrieve the actual file size of a directory entry
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @return int|false The size of the directory entry.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_filesize($zip_entry): int|false {}

/**
 * Retrieve the name of a directory entry
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @return string|false The name of the directory entry.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_name($zip_entry): string|false {}

/**
 * Retrieve the compressed size of a directory entry
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @return int|false The compressed size.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_compressedsize($zip_entry): int|false {}

/**
 * Retrieve the compression method of a directory entry
 * @param resource $zip_entry A directory entry returned by zip_read.
 * @return string|false The compression method.
 * @deprecated 8.0 Use ZipArchive instead.
 */
function zip_entry_compressionmethod($zip_entry): string|false {}
