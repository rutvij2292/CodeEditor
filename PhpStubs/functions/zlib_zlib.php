<?php

/**
 * Output a gz-file
 * @param string $filename The file name. This file will be opened from the filesystem and its contents written to standard output.
 * @param int|bool $use_include_path [optional] You can set this optional parameter to 1, if you want to search for the file in the include_path too.
 * @return int|false the number of (uncompressed) bytes read from the file, or FALSE on error
 */
function readgzfile(string $filename, int $use_include_path = false): int|false {}

/**
 * Rewind the position of a gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return bool TRUE on success or FALSE on failure.
 */
function gzrewind($stream): bool {}

/**
 * Close an open gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return bool TRUE on success or FALSE on failure.
 */
function gzclose($stream): bool {}

/**
 * Test for EOF on a gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return bool TRUE if the gz-file pointer is at EOF or an error occurs; otherwise returns FALSE.
 */
function gzeof($stream): bool {}

/**
 * Get character from gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return string|false The uncompressed character or FALSE on EOF (unlike gzeof).
 */
function gzgetc($stream): string|false {}

/**
 * Get line from file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @param int|null $length The length of data to get.
 * @return string|false The uncompressed string, or FALSE on error.
 */
function gzgets($stream, ?int $length = null): string|false {}

/**
 * Get line from gz-file pointer and strip HTML tags
 * @param resource $zp The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @param int $length [optional] The length of data to get.
 * @param string $allowable_tags [optional] You can use this optional parameter to specify tags which should not be stripped.
 * @return string|false The uncompressed and striped string, or FALSE on error.
 * @removed 8.0
 * @deprecated
 */
function gzgetss($zp, int $length, $allowable_tags) {}

/**
 * Binary-safe gz-file read
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @param int $length The number of bytes to read.
 * @return string|false The data that have been read.
 */
function gzread($stream, int $length): string|false {}

/**
 * Open gz-file
 * @param string $filename The file name.
 * @param string $mode As in fopen (rb or wb) but can also include a compression level (wb9) or a strategy: f for filtered data as in wb6f, h for Huffman only compression as in wb1h. (See the description of deflateInit2 in zlib.h for more information about the strategy parameter.)
 * @param int|bool $use_include_path [optional] You can set this optional parameter to 1, if you want to search for the file in the include_path too.
 * @return resource|false a file pointer to the file opened, after that, everything you read from this file descriptor will be transparently decompressed and what you write gets compressed. If the open fails, the function returns FALSE.
 */
function gzopen(string $filename, string $mode, int $use_include_path = false) {}

/**
 * Output all remaining data on a gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return int The number of uncompressed characters read from gz and passed through to the input. Prior to PHP 8.0, FALSE was returned on error.
 */
function gzpassthru($stream): int {}

/**
 * Seek on a gz-file pointer
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @param int $offset The seeked offset.
 * @param int $whence [optional] whence values are: SEEK_SET - Set position equal to offset bytes. SEEK_CUR - Set position to current location plus offset. If whence is not specified, it is assumed to be SEEK_SET.
 * @return int Upon success, returns 0; otherwise, returns -1. Note that seeking past EOF is not considered an error.
 */
function gzseek($stream, int $offset, int $whence = SEEK_SET): int {}

/**
 * Tell gz-file pointer read/write position
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @return int|false The position of the file pointer or FALSE if an error occurs.
 */
function gztell($stream): int|false {}

/**
 * Binary-safe gz-file write
 * @param resource $stream The gz-file pointer. It must be valid, and must point to a file successfully opened by gzopen.
 * @param string $data The string to write.
 * @param int|null $length [optional] The number of uncompressed bytes to write. If supplied, writing will stop after length (uncompressed) bytes have been written or the end of string is reached, whichever comes first. Note that if the length argument is given, then the magic_quotes_runtime ...
 * @return int|false the number of (uncompressed) bytes written to the given gz-file stream.
 */
function gzwrite($stream, string $data, ?int $length = null): int|false {}

/**
 * Alias of gzwrite
 * @param resource $stream
 * @param string $data
 * @param int|null $length [optional]
 * @return int|false
 */
function gzputs($stream, string $data, ?int $length = null): int|false {}

/**
 * Read entire gz-file into an array
 * @param string $filename The file name.
 * @param int|bool $use_include_path [optional] You can set this optional parameter to 1, if you want to search for the file in the include_path too.
 * @return array|false An array containing the file, one line per cell.
 */
function gzfile(string $filename, int $use_include_path = false): array|false {}

/**
 * Compress a string
 * @param string $data The data to compress.
 * @param int $level [optional] The level of compression. Can be given as 0 for no compression up to 9 for maximum compression. If -1 is used, the default compression of the zlib library is used which is 6.
 * @param int $encoding [optional] One of ZLIB_ENCODING_* constants.
 * @return string|false The compressed string or FALSE if an error occurred.
 */
function gzcompress(string $data, int $level = -1, int $encoding = ZLIB_ENCODING_DEFLATE): string|false {}

/**
 * Uncompress a compressed string
 * @param string $data The data compressed by gzcompress.
 * @param int $max_length [optional] The maximum length of data to decode.
 * @return string|false The original uncompressed data or FALSE on error. The function will return an error if the uncompressed data is more than 32768 times the length of the compressed input data or more than the optional parameter length.
 */
function gzuncompress(string $data, int $max_length = 0): string|false {}

/**
 * Deflate a string
 * @param string $data The data to deflate.
 * @param int $level [optional] The level of compression. Can be given as 0 for no compression up to 9 for maximum compression. If not given, the default compression level will be the default compression level of the zlib library.
 * @param int $encoding [optional] One of ZLIB_ENCODING_* constants.
 * @return string|false The deflated string or FALSE if an error occurred.
 */
function gzdeflate(string $data, int $level = -1, int $encoding = ZLIB_ENCODING_RAW): string|false {}

/**
 * Inflate a deflated string
 * @param string $data The data compressed by gzdeflate.
 * @param int $max_length [optional] The maximum length of data to decode.
 * @return string|false The original uncompressed data or FALSE on error. The function will return an error if the uncompressed data is more than 32768 times the length of the compressed input data or more than the optional parameter length.
 */
function gzinflate(string $data, int $max_length = 0): string|false {}

/**
 * Create a gzip compressed string
 * @param string $data The data to encode.
 * @param int $level [optional] The level of compression. Can be given as 0 for no compression up to 9 for maximum compression. If not given, the default compression level will be the default compression level of the zlib library.
 * @param int $encoding [optional] The encoding mode. Can be FORCE_GZIP (the default) or FORCE_DEFLATE. Prior to PHP 5.4.0, using FORCE_DEFLATE results in a standard zlib deflated string (inclusive zlib headers) after a gzip file header but without the trailing crc32 checksum. In PHP 5.4.0 and later, ...
 * @return string|false The encoded string, or FALSE if an error occurred.
 */
function gzencode(string $data, int $level = -1, int $encoding = FORCE_GZIP): string|false {}

/**
 * Decodes a gzip compressed string
 * @param string $data The data to decode, encoded by gzencode.
 * @param int $max_length The maximum length of data to decode.
 * @return string|false The decoded string, or FALSE if an error occurred.
 * @since 5.4
 */
function gzdecode(string $data, int $max_length = 0): string|false {}

/**
 * Compress data with the specified encoding
 * @param string $data
 * @param int $encoding
 * @param int $level [optional] default -1
 * @return string|false
 * @since 5.4
 */
function zlib_encode(string $data, int $encoding, int $level = -1): string|false {}

/**
 * Uncompress any raw/gzip/zlib encoded data
 * @param string $data
 * @param int $max_length
 * @return string|false
 * @since 5.4
 */
function zlib_decode(string $data, int $max_length = 0): string|false {}

/**
 * Returns the coding type used for output compression
 * @return string|false Possible return values are gzip, deflate, or FALSE.
 */
function zlib_get_coding_type(): string|false {}

/**
 * ob_start callback function to gzip output buffer
 * @param string $data
 * @param int $flags
 * @return string|false
 */
function ob_gzhandler(string $data, int $flags): string|false {}

/**
 * Initialize an incremental deflate context
 * @param int $encoding One of the ZLIB_ENCODING_* constants.
 * @param array|object $options An associative array which may contain the following elements: levelThe compression level in range -1..9; defaults to -1. memoryThe compression memory level in range 1..9; defaults to 8. windowThe zlib window size (logarithmic) in range 8..15; defaults to 15. ...
 * @return resource|false|DeflateContext Returns a deflate context resource (zlib.deflate) on success, or FALSE on failure.
 * @since 7.0
 */
function deflate_init(int $encoding, array|object $options = []): DeflateContext|false {}

/**
 * Incrementally deflate data
 * @param DeflateContext|resource $context A context created with deflate_init().
 * @param string $data A chunk of data to compress.
 * @param int $flush_mode [optional] One of ZLIB_BLOCK, ZLIB_NO_FLUSH, ZLIB_PARTIAL_FLUSH, ZLIB_SYNC_FLUSH (default), ZLIB_FULL_FLUSH, ZLIB_FINISH. Normally you will want to set ZLIB_NO_FLUSH to maximize compression, and ZLIB_FINISH to terminate with the last chunk of data.
 * @return string|false Returns a chunk of compressed data, or FALSE on failure.
 * @since 7.0
 */
function deflate_add(DeflateContext $context, string $data, int $flush_mode = ZLIB_SYNC_FLUSH): string|false {}

/**
 * Initialize an incremental inflate context
 * @param int $encoding One of the ZLIB_ENCODING_* constants.
 * @param array|object $options [optional] An associative array which may contain the following elements: levelThe compression level in range -1..9; defaults to -1. memoryThe compression memory level in range 1..9; defaults to 8. windowThe zlib window size (logarithmic) in range 8..15; defaults to 15. ...
 * @return resource|false|InflateContext Returns an inflate context resource (zlib.inflate) on success, or FALSE on failure.
 * @since 7.0
 */
function inflate_init(int $encoding, array|object $options = []): InflateContext|false {}

/**
 * Incrementally inflate encoded data
 * @param InflateContext|resource $context A context created with inflate_init().
 * @param string $data A chunk of compressed data.
 * @param int $flush_mode [optional] One of ZLIB_BLOCK, ZLIB_NO_FLUSH, ZLIB_PARTIAL_FLUSH, ZLIB_SYNC_FLUSH (default), ZLIB_FULL_FLUSH, ZLIB_FINISH. Normally you will want to set ZLIB_NO_FLUSH to maximize compression, and ZLIB_FINISH to terminate with the last chunk of data.
 * @return string|false Returns a chunk of uncompressed data, or FALSE on failure.
 * @since 7.0
 */
function inflate_add(InflateContext $context, string $data, int $flush_mode = ZLIB_SYNC_FLUSH): string|false {}

/**
 * Get number of bytes read so far
 * @param InflateContext|resource $context
 * @return int
 * @since 7.2
 */
function inflate_get_read_len(InflateContext $context): int {}

/**
 * Get decompression status
 * @param InflateContext|resource $context
 * @return int Returns decompression status.
 * @since 7.2
 */
function inflate_get_status(InflateContext $context): int {}
