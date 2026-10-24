<?php

/**
 * A file archive, compressed with Zip.
 */
class ZipArchive implements Countable
{
    /**
     * Zip library version
     * @since 7.4
     */
    public const LIBZIP_VERSION = '1.7.3';

    /**
     * Create the archive if it does not exist.
     */
    public const CREATE = 1;

    /**
     * Error if archive already exists.
     */
    public const EXCL = 2;

    /**
     * Perform additional consistency checks on the archive, and error if they fail.
     */
    public const CHECKCONS = 4;

    /**
     * Always start a new archive, this mode will overwrite the file if
     * it already exists.
     */
    public const OVERWRITE = 8;

    /**
     * Ignore case on name lookup
     */
    public const FL_NOCASE = 1;

    /**
     * Ignore directory component
     */
    public const FL_NODIR = 2;

    /**
     * Read compressed data
     */
    public const FL_COMPRESSED = 4;

    /**
     * Use original data, ignoring changes.
     */
    public const FL_UNCHANGED = 8;

    /**
     * @since 8.0
     */
    public const FL_RECOMPRESS = 16;

    /**
     * @since 8.0
     */
    public const FL_ENCRYPTED = 32;

    /**
     * @since 8.0
     */
    public const FL_OVERWRITE = 8192;

    /**
     * @since 8.0
     */
    public const FL_LOCAL = 256;

    /**
     * @since 8.0
     */
    public const FL_CENTRAL = 512;

    /**
     * @since 8.0
     */
    public const EM_TRAD_PKWARE = 1;

    /**
     * @since 8.0
     */
    public const EM_UNKNOWN = 65535;

    /**
     * better of deflate or store.
     */
    public const CM_DEFAULT = -1;

    /**
     * stored (uncompressed).
     */
    public const CM_STORE = 0;

    /**
     * shrunk
     */
    public const CM_SHRINK = 1;

    /**
     * reduced with factor 1
     */
    public const CM_REDUCE_1 = 2;

    /**
     * reduced with factor 2
     */
    public const CM_REDUCE_2 = 3;

    /**
     * reduced with factor 3
     */
    public const CM_REDUCE_3 = 4;

    /**
     * reduced with factor 4
     */
    public const CM_REDUCE_4 = 5;

    /**
     * imploded
     */
    public const CM_IMPLODE = 6;

    /**
     * deflated
     */
    public const CM_DEFLATE = 8;

    /**
     * deflate64
     */
    public const CM_DEFLATE64 = 9;

    /**
     * PKWARE imploding
     */
    public const CM_PKWARE_IMPLODE = 10;

    /**
     * BZIP2 algorithm
     */
    public const CM_BZIP2 = 12;

    public const CM_LZMA = 14;

    public const CM_TERSE = 18;

    public const CM_LZ77 = 19;

    public const CM_WAVPACK = 97;

    public const CM_PPMD = 98;

    /**
     * No error.
     */
    public const ER_OK = 0;

    /**
     * Multi-disk zip archives not supported.
     */
    public const ER_MULTIDISK = 1;

    /**
     * Renaming temporary file failed.
     */
    public const ER_RENAME = 2;

    /**
     * Closing zip archive failed
     */
    public const ER_CLOSE = 3;

    /**
     * Seek error
     */
    public const ER_SEEK = 4;

    /**
     * Read error
     */
    public const ER_READ = 5;

    /**
     * Write error
     */
    public const ER_WRITE = 6;

    /**
     * CRC error
     */
    public const ER_CRC = 7;

    /**
     * Containing zip archive was closed
     */
    public const ER_ZIPCLOSED = 8;

    /**
     * No such file.
     */
    public const ER_NOENT = 9;

    /**
     * File already exists
     */
    public const ER_EXISTS = 10;

    /**
     * Can't open file
     */
    public const ER_OPEN = 11;

    /**
     * Failure to create temporary file.
     */
    public const ER_TMPOPEN = 12;

    /**
     * Zlib error
     */
    public const ER_ZLIB = 13;

    /**
     * Memory allocation failure
     */
    public const ER_MEMORY = 14;

    /**
     * Entry has been changed
     */
    public const ER_CHANGED = 15;

    /**
     * Compression method not supported.
     */
    public const ER_COMPNOTSUPP = 16;

    /**
     * Premature EOF
     */
    public const ER_EOF = 17;

    /**
     * Invalid argument
     */
    public const ER_INVAL = 18;

    /**
     * Not a zip archive
     */
    public const ER_NOZIP = 19;

    /**
     * Internal error
     */
    public const ER_INTERNAL = 20;

    /**
     * Zip archive inconsistent
     */
    public const ER_INCONS = 21;

    /**
     * Can't remove file
     */
    public const ER_REMOVE = 22;

    /**
     * Entry has been deleted
     */
    public const ER_DELETED = 23;

    /**
     * No encryption
     * @since 7.2
     */
    public const EM_NONE = 0;

    /**
     * AES 128 encryption
     * @since 7.2
     */
    public const EM_AES_128 = 257;

    /**
     * AES 192 encryption
     * @since 7.2
     */
    public const EM_AES_192 = 258;

    /**
     * AES 256 encryption
     * @since 7.2
     */
    public const EM_AES_256 = 259;

    /**
     * Open archive in read only mode
     * @since 7.4
     */
    public const RDONLY = 16;

    /**
     * Guess string encoding (is default)
     * @since 7.0
     */
    public const FL_ENC_GUESS = 0;

    /**
     * Get unmodified string
     * @since 7.0
     */
    public const FL_ENC_RAW = 64;

    /**
     * Follow specification strictly
     * @since 7.0
     */
    public const FL_ENC_STRICT = 128;

    /**
     * String is UTF-8 encoded
     * @since 7.0
     */
    public const FL_ENC_UTF_8 = 2048;

    /**
     * String is CP437 encoded
     * @since 7.0
     */
    public const FL_ENC_CP437 = 4096;

    /**
     * LZMA2 algorithm
     * @since 7.4
     */
    public const CM_LZMA2 = 33;

    /**
     * XZ algorithm
     * @since 7.4
     */
    public const CM_XZ = 95;

    /**
     * Encryption method not support
     * @since 7.4
     */
    public const ER_ENCRNOTSUPP = 24;

    /**
     * Read-only archive
     * @since 7.4
     */
    public const ER_RDONLY = 25;

    /**
     * No password provided
     * @since 7.4
     */
    public const ER_NOPASSWD = 26;

    /**
     * Wrong password provided
     * @since 7.4
     */
    public const ER_WRONGPASSWD = 27;

    /**
     * Operation not supported
     * @since 7.4
     */
    public const ER_OPNOTSUPP = 28;

    /**
     * Resource still in use
     * @since 7.4
     */
    public const ER_INUSE = 29;

    /**
     * Tell error
     * @since 7.4
     */
    public const ER_TELL = 30;

    /**
     * Compressed data invalid
     * @since 7.4
     */
    public const ER_COMPRESSED_DATA = 31;

    /**
     * Operation cancelled
     * @since 7.4
     */
    public const ER_CANCELLED = 32;

    /**
     * @since 5.6
     */
    public const OPSYS_DOS = 0;

    /**
     * @since 5.6
     */
    public const OPSYS_AMIGA = 1;

    /**
     * @since 5.6
     */
    public const OPSYS_OPENVMS = 2;

    /**
     * @since 5.6
     */
    public const OPSYS_UNIX = 3;

    /**
     * @since 5.6
     */
    public const OPSYS_VM_CMS = 4;

    /**
     * @since 5.6
     */
    public const OPSYS_ATARI_ST = 5;

    /**
     * @since 5.6
     */
    public const OPSYS_OS_2 = 6;

    /**
     * @since 5.6
     */
    public const OPSYS_MACINTOSH = 7;

    /**
     * @since 5.6
     */
    public const OPSYS_Z_SYSTEM = 8;

    /**
     * @removed 8.0 Use ZipArchive::ZOPSYS_CPM instead.
     * @since 5.6
     */
    public const OPSYS_Z_CPM = 9;

    /**
     * @since 5.6
     */
    public const OPSYS_WINDOWS_NTFS = 10;

    /**
     * @since 5.6
     */
    public const OPSYS_MVS = 11;

    /**
     * @since 5.6
     */
    public const OPSYS_VSE = 12;

    /**
     * @since 5.6
     */
    public const OPSYS_ACORN_RISC = 13;

    /**
     * @since 5.6
     */
    public const OPSYS_VFAT = 14;

    /**
     * @since 5.6
     */
    public const OPSYS_ALTERNATE_MVS = 15;

    /**
     * @since 5.6
     */
    public const OPSYS_BEOS = 16;

    /**
     * @since 5.6
     */
    public const OPSYS_TANDEM = 17;

    /**
     * @since 5.6
     */
    public const OPSYS_OS_400 = 18;

    /**
     * @since 5.6
     */
    public const OPSYS_OS_X = 19;

    public const OPSYS_CPM = 9;

    /**
     * @since 5.6
     */
    public const OPSYS_DEFAULT = 3;

    /**
     * @since 8.0
     */
    public const FL_OPEN_FILE_NOW = 1073741824;

    /**
     * @since 8.0
     */
    public const CM_ZSTD = 93;

    /**
     * @since 8.0
     */
    public const ER_DATA_LENGTH = 33;

    /**
     * @since 8.0
     */
    public const ER_NOT_ALLOWED = 34;

    /**
     * @since 8.0
     */
    public const AFL_RDONLY = 2;

    /**
     * @since 8.0
     */
    public const AFL_IS_TORRENTZIP = 4;

    /**
     * @since 8.0
     */
    public const AFL_WANT_TORRENTZIP = 8;

    /**
     * @since 8.0
     */
    public const AFL_CREATE_OR_KEEP_FILE_FOR_EMPTY_ARCHIVE = 16;

    /**
     * @since 8.0
     */
    public const LENGTH_TO_END = 0;

    /**
     * @since 8.0
     */
    public const LENGTH_UNCHECKED = -2;

    /**
     * Status of the Zip Archive
     * @var int
     */
    public int $status;

    /**
     * System status of the Zip Archive
     * @var int
     */
    public int $statusSys;

    /**
     * Number of files in archive
     * @var int
     */
    public int $numFiles;

    /**
     * File name in the file system
     * @var string
     */
    public string $filename;

    /**
     * Comment for the archive
     * @var string
     */
    public string $comment;

    /**
     * @var int
     */
    public int $lastId;

    /**
     * Open a ZIP file archive
     * @param string $filename The file name of the ZIP archive to open.
     * @param int $flags [optional] The mode to use to open the archive. ZipArchive::OVERWRITE If archive exists, ignore its current contents. In other words, handle it the same way as an empty archive ZipArchive::CREATE Create the archive if it does not exist ZipArchive::RDONLY Open archive in read only ...
     * @return int|bool Error codes Returns TRUE on success, FALSE or the error code on error. ZipArchive::ER_EXISTS File already exists ZipArchive::ER_INCONS Zip archive inconsistent ZipArchive::ER_INVAL Invalid argument ZipArchive::ER_MEMORY Malloc failure ZipArchive::ER_NOENT No such file ...
     */
    public function open(
        string $filename,
        int $flags = null
    ): int|bool {}

    /**
     * Close the active archive (opened or newly created)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function close(): bool {}

    /**
     * Counts the number of files in the archive.
     * @return int Returns the number of files in the archive.
     * @since 7.2
     */
    public function count(): int {}

    /**
     * Returns the status error message, system and/or zip messages
     * @return string|false a string with the status message on success or FALSE on failure.
     * @since 5.2
     */
    public function getStatusString(): string {}

    /**
     * Add a new directory
     * @param string $dirname The directory to add.
     * @param int $flags [optional] Set how to manage name encoding (ZipArchive::FL_ENC_*) and entry replacement (ZipArchive::FL_OVERWRITE)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function addEmptyDir(
        string $dirname,
        int $flags = 0
    ): bool {}

    /**
     * Add a file to a ZIP archive using its contents
     * @param string $name The name of the entry to create.
     * @param string $content The contents to use to create the entry. It is used in a binary safe mode.
     * @param int $flags [optional] Set how to manage name encoding (ZipArchive::FL_ENC_*) and entry replacement (ZipArchive::FL_OVERWRITE)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function addFromString(
        string $name,
        string $content,
        int $flags = 8192
    ): bool {}

    /**
     * Adds a file to a ZIP archive from the given path
     * @param string $filepath The path to the file to add.
     * @param string $entryname [optional] If supplied, this is the local name inside the ZIP archive that will override the filename.
     * @param int $start [optional] This parameter is not used but is required to extend ZipArchive.
     * @param int $length [optional] This parameter is not used but is required to extend ZipArchive.
     * @param int $flags [optional] Set how to manage name encoding (ZipArchive::FL_ENC_*) and entry replacement (ZipArchive::FL_OVERWRITE)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function addFile(
        string $filepath,
        string $entryname = null,
        int $start = 0,
        int $length = 0,
        int $flags = 8192
    ): bool {}

    /**
     * Add files from a directory by glob pattern
     * @param string $pattern A glob pattern against which files will be matched.
     * @param int $flags [optional] A bit mask of glob() flags.
     * @param array $options [optional] An associative array of options. Available options are: "add_path" Prefix to prepend when translating to the local path of the file within the archive. This is applied after any remove operations defined by the "remove_path" or "remove_all_path" options.
     * @return array|false An array of added files on success or false on failure
     */
    public function addGlob(
        string $pattern,
        int $flags = 0,
        array $options = []
    ): array|false {}

    /**
     * Add files from a directory by PCRE pattern
     * @param string $pattern A PCRE pattern against which files will be matched.
     * @param string $path [optional] The directory that will be scanned. Defaults to the current working directory.
     * @param array $options [optional] An associative array of options accepted by ZipArchive::addGlob.
     * @return array|false An array of added files on success or false on failure
     */
    public function addPattern(
        string $pattern,
        string $path = '.',
        array $options = []
    ): array|false {}

    /**
     * Renames an entry defined by its index
     * @param int $index Index of the entry to rename.
     * @param string $new_name New name.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function renameIndex(
        int $index,
        string $new_name
    ): bool {}

    /**
     * Renames an entry defined by its name
     * @param string $name Name of the entry to rename.
     * @param string $new_name New name.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function renameName(
        string $name,
        string $new_name
    ): bool {}

    /**
     * Set the comment of a ZIP archive
     * @param string $comment The contents of the comment.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setArchiveComment(string $comment): bool {}

    /**
     * Returns the Zip archive comment
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged comment is returned.
     * @return string|false the Zip archive comment or FALSE on failure.
     */
    public function getArchiveComment(int $flags = null): string|false {}

    /**
     * Set the comment of an entry defined by its index
     * @param int $index Index of the entry.
     * @param string $comment The contents of the comment.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setCommentIndex(
        int $index,
        string $comment
    ): bool {}

    /**
     * Set the comment of an entry defined by its name
     * @param string $name Name of the entry.
     * @param string $comment The contents of the comment.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setCommentName(
        string $name,
        string $comment
    ): bool {}

    /**
     * Set the compression method of an entry defined by its index
     * @param int $index Index of the entry.
     * @param int $method The compression method. Either ZipArchive::CM_DEFAULT, ZipArchive::CM_STORE or ZipArchive::CM_DEFLATE.
     * @param int $compflags [optional] Compression flags. Currently unused.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 7.0
     */
    public function setCompressionIndex(int $index, int $method, int $compflags = 0): bool {}

    /**
     * Set the compression method of an entry defined by its name
     * https://secure.php.net/manual/en/ziparchive.setcompressionname.php
     * @param string $name Name of the entry.
     * @param int $method The compression method. Either ZipArchive::CM_DEFAULT, ZipArchive::CM_STORE or ZipArchive::CM_DEFLATE.
     * @param int $compflags [optional] Compression flags. Currently unused.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 7.0
     */
    public function setCompressionName(string $name, int $method, int $compflags = 0): bool {}

    /**
     * Set the encryption method of an entry defined by its index
     * @param int $index Index of the entry.
     * @param int $method The encryption method defined by one of the ZipArchive::EM_ constants.
     * @param string|null $password [optional] Optional password, default used when missing.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 7.2
     */
    public function setEncryptionIndex(int $index, int $method, ?string $password = null): bool {}

    /**
     * Set the encryption method of an entry defined by its name
     * @param string $name Name of the entry.
     * @param int $method The encryption method defined by one of the ZipArchive::EM_ constants.
     * @param string|null $password [optional] Optional password, default used when missing.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 7.2
     */
    public function setEncryptionName(string $name, int $method, ?string $password = null): bool {}

    /**
     * @param string $password The password to be used for the archive.
     * @return bool Returns true on success or false on failure.
     */
    public function setPassword(string $password): bool {}

    /**
     * Returns the comment of an entry using the entry index
     * @param int $index Index of the entry
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged comment is returned.
     * @return string|false the comment on success or FALSE on failure.
     */
    public function getCommentIndex(
        int $index,
        int $flags = null
    ): string|false {}

    /**
     * Returns the comment of an entry using the entry name
     * @param string $name Name of the entry
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged comment is returned.
     * @return string|false the comment on success or FALSE on failure.
     */
    public function getCommentName(
        string $name,
        int $flags = null
    ): string|false {}

    /**
     * delete an entry in the archive using its index
     * @param int $index Index of the entry to delete.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function deleteIndex(int $index): bool {}

    /**
     * delete an entry in the archive using its name
     * @param string $name Name of the entry to delete.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function deleteName(string $name): bool {}

    /**
     * Get the details of an entry defined by its name.
     * @param string $name Name of the entry
     * @param int $flags [optional] The flags argument specifies how the name lookup should be done. Also, ZipArchive::FL_UNCHANGED may be ORed to it to request information about the original file in the archive, ignoring any changes made. ZipArchive::FL_NOCASE
     * @return array{name: string, index: int, crc: int, size: int, mtime: int, comp_size: int, comp_method: int, encryption_method: int}|false an array containing the entry details or FALSE on failure.
     */
    public function statName(
        string $name,
        int $flags = null
    ): array|false {}

    /**
     * Get the details of an entry defined by its index.
     * @param int $index Index of the entry
     * @param int $flags [optional] ZipArchive::FL_UNCHANGED may be ORed to it to request information about the original file in the archive, ignoring any changes made.
     * @return array{name: string, index: int, crc: int, size: int, mtime: int, comp_size: int, comp_method: int, encryption_method: int}|false an array containing the entry details or FALSE on failure.
     */
    public function statIndex(
        int $index,
        int $flags = null
    ): array|false {}

    /**
     * Returns the index of the entry in the archive
     * @param string $name The name of the entry to look up
     * @param int $flags [optional] The flags are specified by ORing the following values, or 0 for none of them. ZipArchive::FL_NOCASE
     * @return int|false the index of the entry on success or FALSE on failure.
     */
    public function locateName(
        string $name,
        int $flags = null
    ): int|false {}

    /**
     * Returns the name of an entry using its index
     * @param int $index Index of the entry.
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged name is returned.
     * @return string|false the name on success or FALSE on failure.
     */
    public function getNameIndex(
        int $index,
        int $flags = null
    ): string|false {}

    /**
     * Revert all global changes done in the archive.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function unchangeArchive(): bool {}

    /**
     * Undo all changes done in the archive
     * @return bool TRUE on success or FALSE on failure.
     */
    public function unchangeAll(): bool {}

    /**
     * Revert all changes done to an entry at the given index
     * @param int $index Index of the entry.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function unchangeIndex(int $index): bool {}

    /**
     * Revert all changes done to an entry with the given name.
     * @param string $name Name of the entry.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function unchangeName(string $name): bool {}

    /**
     * Extract the archive contents
     * @param string $pathto Location where to extract the files.
     * @param string[]|string|null $files [optional] The entries to extract. It accepts either a single entry name or an array of names.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function extractTo(
        string $pathto,
        array|string|null $files = null
    ): bool {}

    /**
     * Returns the entry contents using its name
     * @param string $name Name of the entry
     * @param int $len [optional] The length to be read from the entry. If 0, then the entire entry is read.
     * @param int $flags [optional] The flags to use to open the archive. the following values may be ORed to it. ZipArchive::FL_UNCHANGED
     * @return string|false the contents of the entry on success or FALSE on failure.
     */
    public function getFromName(
        string $name,
        int $len = 0,
        int $flags = null
    ): string|false {}

    /**
     * Returns the entry contents using its index
     * @param int $index Index of the entry
     * @param int $len [optional] The length to be read from the entry. If 0, then the entire entry is read.
     * @param int $flags [optional] The flags to use to open the archive. the following values may be ORed to it. ZipArchive::FL_UNCHANGED
     * @return string|false the contents of the entry on success or FALSE on failure.
     */
    public function getFromIndex(
        int $index,
        int $len = 0,
        int $flags = null
    ): string|false {}

    /**
     * Get a file handler to the entry defined by its name (read only).
     * @param string $name The name of the entry to use.
     * @return resource|false a file pointer (resource) on success or FALSE on failure.
     */
    public function getStream(string $name) {}

    /**
     * Get a file handler to the entry defined by its index (read only)
     * @param int $index Index of the entry
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged stream is returned.
     * @return resource|false a file pointer (resource) on success or FALSE on failure.
     */
    public function getStreamIndex(
        int $index,
        int $flags = 0
    ) {}

    /**
     * Set the external attributes of an entry defined by its name
     * @param string $name Name of the entry
     * @param int $opsys The operating system code defined by one of the ZipArchive::OPSYS_ constants.
     * @param int $attr The external attributes. Value depends on operating system.
     * @param int $flags [optional] Optional flags. Currently unused.
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function setExternalAttributesName(
        string $name,
        int $opsys,
        int $attr,
        int $flags = null
    ): bool {}

    /**
     * Retrieve the external attributes of an entry defined by its name
     * @param string $name Name of the entry
     * @param int &$opsys On success, receive the operating system code defined by one of the ZipArchive::OPSYS_ constants.
     * @param int &$attr On success, receive the external attributes. Value depends on operating system.
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged attributes are returned.
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function getExternalAttributesName(
        string $name,
        int &$opsys,
        int &$attr,
        int $flags = null
    ): bool {}

    /**
     * Set the external attributes of an entry defined by its index
     * @param int $index Index of the entry.
     * @param int $opsys The operating system code defined by one of the ZipArchive::OPSYS_ constants.
     * @param int $attr The external attributes. Value depends on operating system.
     * @param int $flags [optional] Optional flags. Currently unused.
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function setExternalAttributesIndex(
        int $index,
        int $opsys,
        int $attr,
        int $flags = null
    ): bool {}

    /**
     * Retrieve the external attributes of an entry defined by its index
     * @param int $index Index of the entry.
     * @param int &$opsys On success, receive the operating system code defined by one of the ZipArchive::OPSYS_ constants.
     * @param int &$attr On success, receive the external attributes. Value depends on operating system.
     * @param int $flags [optional] If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged attributes are returned.
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function getExternalAttributesIndex(
        int $index,
        int &$opsys,
        int &$attr,
        int $flags = null
    ): bool {}

    /**
     * Check if a encryption method is supported by libzip
     *
     * Check if a compression method is supported by libzip.
     * @param int $method The encryption method, one of the ZipArchive::EM_* constants.
     * @param bool $enc If true check for encryption, else check for decryption.
     */
    public static function isEncryptionMethodSupported(
        int $method,
        bool $enc = true
    ): bool {}

    /**
     * Check if a compression method is supported by libzip
     * @param int $method The compression method, one of the ZipArchive::CM_* constants.
     * @param bool $enc If true check for compression, else check for decompression.
     */
    public static function isCompressionMethodSupported(
        int $method,
        bool $enc = true
    ): bool {}

    /**
     * Register a callback to allow cancellation during archive close.
     *
     * Register a callback function to allow cancellation during archive close.
     * @param callable $callback If this function return 0 operation will continue, other value it will be cancelled.
     * @return bool Returns true on success or false on failure.
     */
    public function registerCancelCallback(callable $callback): bool {}

    /**
     * Register a callback to provide updates during archive close.
     *
     * Register a callback function to provide updates during archive close.
     * @param float $rate Change between each call of the callback (from 0.0 to 1.0).
     * @param callable $callback This function will receive the current state as a float (from 0.0 to 1.0).
     * @return bool Returns true on success or false on failure.
     */
    public function registerProgressCallback(
        float $rate,
        callable $callback
    ): bool {}

    /**
     * Set the modification time of an entry defined by its name
     * @param string $name Name of the entry.
     * @param int $timestamp The modification time (unix timestamp) of the file.
     * @param int $flags Optional flags, unused for now.
     * @return bool Returns true on success or false on failure.
     */
    public function setMtimeName(
        string $name,
        int $timestamp,
        int $flags = null
    ): bool {}

    /**
     * Set the modification time of an entry defined by its index
     * @param int $index Index of the entry.
     * @param int $timestamp The modification time (unix timestamp) of the file.
     * @param int $flags Optional flags, unused for now.
     * @return bool Returns true on success or false on failure.
     */
    public function setMtimeIndex(
        int $index,
        int $timestamp,
        int $flags = null
    ): bool {}

    /**
     * Replace file in ZIP archive with a given path
     * @param string $filepath The path to the file to add.
     * @param int $index The index of the file to be replaced, its name is unchanged.
     * @param int $start For partial copy, start position.
     * @param int $length For partial copy, length to be copied, if ZipArchive::LENGTH_TO_END (0) the file size is used, if ZipArchive::LENGTH_UNCHECKED the whole file is used (starting from start).
     * @param int $flags Bitmask consisting of ZipArchive::FL_ENC_GUESS, ZipArchive::FL_ENC_UTF_8, ZipArchive::FL_ENC_CP437, ZipArchive::FL_OPEN_FILE_NOW. The behaviour of these constants is described on the ZIP constants page.
     * @return bool Returns true on success or false on failure.
     */
    public function replaceFile(
        string $filepath,
        int $index,
        int $start = null,
        int $length = null,
        int $flags = null
    ): bool {}

    /**
     * Clear the status error message, system and/or zip messages
     */
    public function clearError(): void {}

    /**
     * Set a global flag of a ZIP archive
     * @param int $flag The global flag to change, among AFL_* constants. ZipArchive::AFL_WANT_TORRENTZIP ZipArchive::AFL_CREATE_OR_KEEP_FILE_FOR_EMPTY_ARCHIVE
     * @param int $value The new value of the flag.
     * @return bool Returns true on success or false on failure.
     */
    public function setArchiveFlag(
        int $flag,
        int $value
    ): bool {}

    /**
     * Returns the value of a Zip archive global flag
     *
     * Returns a Zip archive global flag value.
     * @param int $flag The global flag to retrieve, among AFL_* constants: ZipArchive::AFL_RDONLY ZipArchive::AFL_IS_TORRENTZIP ZipArchive::AFL_WANT_TORRENTZIP ZipArchive::AFL_CREATE_OR_KEEP_FILE_FOR_EMPTY_ARCHIVE
     * @param int $flags If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged flag is returned.
     * @return int Returns 1 if flag is set for archive, 0 if not, and -1 if an error occurred.
     */
    public function getArchiveFlag(
        int $flag,
        int $flags = 0
    ): int {}

    /**
     * Get a file handler to the entry defined by its name (read only)
     *
     * Get a file handler to the entry defined by its name. For now, it only supports read
     * operations.
     * @param string $name The name of the entry to use.
     * @param int $flags If flags is set to ZipArchive::FL_UNCHANGED, the original unchanged stream is returned.
     * @return void Returns a file pointer (resource) on success or false on failure.
     */
    public function getStreamName(
        string $name,
        int $flags = 0
    ) {}

    /**
     * @return array
     * @since 8.6
     */
    public function __serialize(): array {}

    /**
     * @param array $data
     * @return void
     * @since 8.6
     */
    public function __unserialize(array $data): void {}

    /**
     * @return string|false
     * @since 8.6
     */
    public function closeString(): string|false {}

    /**
     * @param string $data
     * @param int $flags
     * @return int|bool
     * @since 8.6
     */
    public function openString(string $data = '', int $flags = 0): int|bool {}
}
