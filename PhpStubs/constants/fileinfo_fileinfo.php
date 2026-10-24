<?php

/**
 * No special handling.
 */
const FILEINFO_NONE = 0;

/**
 * Follow symlinks.
 */
const FILEINFO_SYMLINK = 2;

/**
 * Return the mime type and mime encoding as defined by RFC 2045.
 */
const FILEINFO_MIME = 1040;

/**
 * Return the mime type.
 */
const FILEINFO_MIME_TYPE = 16;

/**
 * Return the mime encoding of the file.
 */
const FILEINFO_MIME_ENCODING = 1024;

/**
 * Look at the contents of blocks or character special devices.
 */
const FILEINFO_DEVICES = 8;

/**
 * Return all matches, not just the first.
 */
const FILEINFO_CONTINUE = 32;

/**
 * If possible preserve the original access time.
 */
const FILEINFO_PRESERVE_ATIME = 128;

/**
 * Don't translate unprintable characters to a \ooo octal
 * representation.
 */
const FILEINFO_RAW = 256;

/**
 * Returns the file extension appropriate for a the MIME type detected in the file.
 * For types that commonly have multiple file extensions, such as JPEG images, then the return value is multiple extensions speparated by a forward slash e.g.: "jpeg/jpg/jpe/jfif".
 * For unknown types not available in the magic.mime database, then return value is "???". Available since PHP 7.2.0.
 * @since 7.2
 */
const FILEINFO_EXTENSION = 2097152;

/**
 * @since 8.2
 */
const FILEINFO_APPLE = 2048;
