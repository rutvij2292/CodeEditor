<?php

/**
 * The PharFileInfo class provides a high-level interface to the contents
 * and attributes of a single file within a phar archive.
 */
class PharFileInfo extends SplFileInfo
{
    /**
     * Construct a Phar entry object
     * @param string $filename The full url to retrieve a file. If you wish to retrieve the information for the file my/file.php from the phar boo.phar, the entry should be phar://boo.phar/my/file.php.
     * @throws \BadMethodCallException Throws BadMethodCallException if __construct() is called twice.
     * @throws \UnexpectedValueException Throws UnexpectedValueException if the phar URL requested is malformed, the requested phar cannot be opened, or the file can't be found within the phar.
     */
    public function __construct(string $filename) {}

    /**
     * Destructs a Phar entry object
     */
    public function __destruct() {}

    /**
     * Sets file-specific permission bits
     * @param int $perms permissions (see chmod)
     * @return void No value is returned.
     */
    public function chmod(int $perms): void {}

    /**
     * Compresses the current Phar entry with either zlib or bzip2 compression
     * @param int $compression Compression must be Phar::GZ or Phar::BZ2.
     * @return bool TRUE on success or FALSE on failure.
     * @throws \BadMethodCallException Throws BadMethodCallException if the phar.readonly INI variable is on, or if the bzip2/zlib extension is not available.
     */
    public function compress(int $compression): bool {}

    /**
     * Decompresses the current Phar entry within the phar
     * @return bool TRUE on success or FALSE on failure.
     * @throws \BadMethodCallException Throws BadMethodCallException if the phar.readonly INI variable is on, or if the bzip2/zlib extension is not available.
     */
    public function decompress(): bool {}

    /**
     * Deletes the metadata of the entry
     * @return bool TRUE if successful, FALSE if the entry had no metadata. As with all functionality that modifies the contents of a phar, the phar.readonly INI variable must be off in order to succeed if the file is within a Phar archive. Files within PharData archives do not have this restriction.
     * @throws \PharException Throws PharException if errors occurred while flushing changes to disk.
     * @throws \BadMethodCallException Throws BadMethodCallException if write access is disabled.
     */
    public function delMetadata(): bool {}

    /**
     * Returns the actual size of the file (with compression) inside the Phar archive
     * @return int<0, max> The size in bytes of the file within the Phar archive on disk.
     */
    public function getCompressedSize(): int {}

    /**
     * Returns CRC32 code or throws an exception if CRC has not been verified
     * @return int The crc32 checksum of the file within the Phar archive.
     * @throws \BadMethodCallException Throws BadMethodCallException if the file has not yet had its CRC32 verified. This should be impossible with normal use, as the CRC is verified upon opening the file for reading or writing.
     */
    public function getCRC32(): int {}

    /**
     * Get the complete file contents of the entry
     *
     * This function behaves like file_get_contents but for Phar.
     * @return string Returns the file contents.
     */
    public function getContent(): string {}

    /**
     * Returns file-specific meta-data saved with a file
     * @param array $unserializeOptions [optional] if is set to anything other than the default, the resulting metadata won't be cached and this won't return the value from the cache
     * @return mixed any PHP variable that can be serialized and is stored as meta-data for the file, or NULL if no meta-data is stored.
     */
    public function getMetadata(array $unserializeOptions = []): mixed {}

    /**
     * Returns the Phar file entry flags
     * @return int The Phar flags (always 0 in the current implementation)
     */
    public function getPharFlags(): int {}

    /**
     * Returns the metadata of the entry
     * @return bool FALSE if no metadata is set or is NULL, TRUE if metadata is not NULL
     */
    public function hasMetadata(): bool {}

    /**
     * Returns whether the entry is compressed
     * @param int $compression [optional] One of Phar::GZ or Phar::BZ2, defaults to any compression.
     * @return bool TRUE if the file is compressed within the Phar archive, FALSE if not.
     */
    public function isCompressed(int|null $compression = null): bool {}

    /**
     * Returns whether file entry has had its CRC verified
     * @return bool TRUE if the file has had its CRC verified, FALSE if not.
     */
    public function isCRCChecked(): bool {}

    /**
     * Sets file-specific meta-data saved with a file
     * @param mixed $metadata Any PHP variable containing information to store alongside a file
     * @return void No value is returned.
     */
    public function setMetadata(mixed $metadata): void {}
}
