<?php

/**
 * The PharData class provides a high-level interface to accessing and creating
 * non-executable tar and zip archives. Because these archives do not contain
 * a stub and cannot be executed by the phar extension, it is possible to create
 * and manipulate regular zip and tar files using the PharData class even if
 * phar.readonly php.ini setting is 1.
 */
class PharData extends RecursiveDirectoryIterator implements Countable, ArrayAccess
{
    /**
     * Construct a non-executable tar or zip archive object
     * @param string $filename Path to an existing tar/zip archive or to-be-created archive
     * @param int $flags [optional] Flags to pass to Phar parent class RecursiveDirectoryIterator.
     * @param string $alias [optional] Alias with which this Phar archive should be referred to in calls to stream functionality.
     * @param int $format [optional] One of the file format constants available within the Phar class.
     * @throws \BadMethodCallException Throws BadMethodCallException if called twice;
     * @throws \UnexpectedValueException UnexpectedValueException if the Phar archive can't be opened.
     */
    public function __construct(
        string $filename,
        int $flags = FilesystemIterator::SKIP_DOTS|FilesystemIterator::UNIX_PATHS,
        string|null $alias = null,
        int $format = 0
    ) {}

    /**
     * @param string $localName
     * @return bool
     */
    public function offsetExists($localName): bool {}

    /**
     * @param string $localName
     * @return SplFileInfo
     */
    public function offsetGet($localName): SplFileInfo {}

    /**
     * set the contents of a file within the tar/zip to those of an external file or string
     * @param string $localName The filename (relative path) to modify in a tar or zip archive.
     * @param string $value Content of the file.
     * @return void No return values.
     * @throws \PharException Throws PharException if there are any problems flushing changes made to the tar/zip archive to disk.
     */
    public function offsetSet($localName, $value): void {}

    /**
     * remove a file from a tar/zip archive
     * @param string $localName The filename (relative path) to modify in the tar/zip archive.
     * @return void No value is returned.
     * @throws \PharException Throws PharException if there are any problems flushing changes made to the tar/zip archive to disk.
     */
    public function offsetUnset($localName): void {}

    /**
     * Returns whether current entry is a directory and not '.' or '..'
     * @param bool $allowLinks [optional]
     * @return bool whether the current entry is a directory, but not '.' or '..'
     */
    public function hasChildren(bool $allowLinks = false): bool {}

    /**
     * Returns an iterator for the current entry if it is a directory
     * @return RecursiveDirectoryIterator An iterator for the current entry, if it is a directory.
     */
    public function getChildren(): RecursiveDirectoryIterator {}

    /**
     * Rewinds back to the beginning
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Move to the next file
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Retrieve the key for the current file
     * @return string the pathname or filename depending on the set flags. See the FilesystemIterator constants.
     */
    public function key(): string {}

    /**
     * The current file
     * @return mixed The filename, file information, or $this depending on the set flags. See the FilesystemIterator constants.
     */
    public function current(): SplFileInfo|FilesystemIterator|string {}

    /**
     * Check whether current DirectoryIterator position is a valid file
     * @return bool TRUE if the position is valid, otherwise FALSE
     */
    public function valid(): bool {}

    /**
     * (Unknown)
     *
     * Add an empty directory to the phar archive
     * @param string $directory The name of the empty directory to create in the phar archive
     * @return void no return value, exception is thrown on failure.
     */
    public function addEmptyDir(
        string $directory
    ): void {}

    /**
     * (Unknown)
     *
     * Add a file from the filesystem to the phar archive
     * @param string $filename Full or relative path to a file on disk to be added to the phar archive.
     * @param string $localName [optional] Path that the file will be stored in the archive.
     * @return void no return value, exception is thrown on failure.
     */
    public function addFile(
        string $filename,
        string|null $localName = null
    ): void {}

    /**
     * (Unknown)
     *
     * Add a file from the filesystem to the phar archive
     * @param string $localName Path that the file will be stored in the archive.
     * @param string $contents The file contents to store
     * @return void no return value, exception is thrown on failure.
     */
    public function addFromString(
        string $localName,
        string $contents
    ): void {}

    /**
     * Construct a phar archive from the files within a directory.
     * @param string $directory The full or relative path to the directory that contains all files to add to the archive.
     * @param $pattern $regex [optional] An optional pcre regular expression that is used to filter the list of files. Only file paths matching the regular expression will be included in the archive.
     * @return array Phar::buildFromDirectory returns an associative array mapping internal path of file to the full path of the file on the filesystem.
     * @throws \BadMethodCallException This method throws BadMethodCallException when unable to instantiate the internal directory iterators
     * @throws \PharException This method throws a PharException if there were errors saving the phar archive.
     */
    public function buildFromDirectory(
        string $directory,
        string $pattern = ''
    ): array {}

    /**
     * Construct a phar archive from an iterator.
     * @param Traversable $iterator Any iterator that either associatively maps phar file to location or returns SplFileInfo objects
     * @param string $baseDirectory [optional] For iterators that return SplFileInfo objects, the portion of each file's full path to remove when adding to the phar archive
     * @return array Phar::buildFromIterator returns an associative array mapping internal path of file to the full path of the file on the filesystem.
     * @throws \UnexpectedValueException This method returns UnexpectedValueException when the iterator returns incorrect values, such as an integer key instead of a string.
     * @throws \BadMethodCallException This method returns a BadMethodCallException when an SplFileInfo-based iterator is passed without a baseDirectory parameter
     * @throws \PharException This method returns a PharException if there were errors saving the phar archive.
     */
    public function buildFromIterator(
        Traversable $iterator,
        string|null $baseDirectory = null
    ): array {}

    /**
     * Compresses all files in the current Phar archive
     * @param int $compression Compression must be one of Phar::GZ, Phar::BZ2 to add compression, or Phar::NONE to remove compression.
     * @return void No value is returned.
     * @throws \BadMethodCallException Throws BadMethodCallException if the phar.readonly INI variable is on, the zlib extension is not available, or if any files are compressed using bzip2 compression and the bzip2 extension is not enabled.
     */
    public function compressFiles(int $compression): void {}

    /**
     * Decompresses all files in the current Phar archive
     * @return bool TRUE on success or FALSE on failure.
     * @throws \BadMethodCallException Throws BadMethodCallException if the zlib extension is not available, or if any files are compressed using bzip2 compression and the bzip2 extension is not enabled.
     */
    public function decompressFiles(): bool {}

    /**
     * Compresses the entire Phar archive using Gzip or Bzip2 compression
     * @param int $compression Compression must be one of Phar::GZ, Phar::BZ2 to add compression, or Phar::NONE to remove compression.
     * @param string $extension [optional] By default, the extension is .phar.gz or .phar.bz2 for compressing phar archives, and .phar.tar.gz or .phar.tar.bz2 for compressing tar archives. For decompressing, the default file extensions are .phar and .phar.tar.
     * @return static|null a Phar object.
     * @throws \BadMethodCallException Throws BadMethodCallException if the zlib extension is not available, or the bzip2 extension is not enabled.
     */
    public function compress(
        int $compression,
        string|null $extension = null
    ): static|null {}

    /**
     * Decompresses the entire Phar archive
     * @param string $extension [optional] For decompressing, the default file extensions are .phar and .phar.tar. Use this parameter to specify another file extension. Be aware that all executable phar archives must contain .phar in their filename.
     * @return static|null A Phar object is returned.
     * @throws \BadMethodCallException Throws BadMethodCallException if the zlib extension is not available, or the bzip2 extension is not enabled.
     */
    public function decompress(string|null $extension = null): static|null {}

    /**
     * Convert a phar archive to another executable phar archive file format
     * @param int $format [optional] This should be one of Phar::PHAR, Phar::TAR, or Phar::ZIP. If set to NULL, the existing file format will be preserved.
     * @param int $compression [optional] This should be one of Phar::NONE for no whole-archive compression, Phar::GZ for zlib-based compression, and Phar::BZ2 for bzip-based compression.
     * @param string $extension [optional] This parameter is used to override the default file extension for a converted archive. Note that all zip- and tar-based phar archives must contain .phar in their file extension in order to be processed as a phar archive. If converting to a phar-based archive, the ...
     * @return Phar|null The method returns a Phar object on success and throws an exception on failure.
     * @throws \BadMethodCallException This method throws BadMethodCallException when unable to compress, an unknown compression method has been specified, the requested archive is buffering with Phar::startBuffering and has not concluded with Phar::stopBuffering.
     * @throws \UnexpectedValueException This method throws an UnexpectedValueException if write support is disabled.
     * @throws \PharException This method throws a PharException if any problems are encountered during the phar creation process.
     */
    public function convertToExecutable(
        int|null $format = null,
        int|null $compression = null,
        string|null $extension = null
    ): ?Phar {}

    /**
     * Convert a phar archive to a non-executable tar or zip file
     * @param int $format [optional] This should be one of Phar::TAR or Phar::ZIP. If set to NULL, the existing file format will be preserved.
     * @param int $compression [optional] This should be one of Phar::NONE for no whole-archive compression, Phar::GZ for zlib-based compression, and Phar::BZ2 for bzip-based compression.
     * @param string $extension [optional] This parameter is used to override the default file extension for a converted archive. Note that .phar cannot be used anywhere in the filename for a non-executable tar or zip archive. If converting to a tar-based phar archive, the default extensions are .tar, ...
     * @return PharData|null The method returns a PharData object on success and throws an exception on failure.
     * @throws \BadMethodCallException This method throws BadMethodCallException when unable to compress, an unknown compression method has been specified, the requested archive is buffering with Phar::startBuffering and has not concluded with Phar::stopBuffering.
     * @throws \PharException This method throws a PharException if any problems are encountered during the phar creation process.
     */
    public function convertToData(
        int|null $format = null,
        int|null $compression = null,
        string|null $extension = null
    ): ?PharData {}

    /**
     * Copy a file internal to the phar archive to another new file within the phar
     * @param string $from
     * @param string $to
     * @return bool returns TRUE on success, but it is safer to encase method call in a try/catch block and assume success if no exception is thrown.
     * @throws \UnexpectedValueException Throws UnexpectedValueException if the source file does not exist, the destination file already exists, write access is disabled, opening either file fails, reading the source file fails.
     * @throws \PharException Throws a PharException if writing the changes to the phar fails.
     */
    public function copy(
        string $from,
        string $to
    ): bool {}

    /**
     * Returns the number of entries (files) in the Phar archive
     * @param int $mode [optional]
     * @return int<0,max> The number of files contained within this phar, or 0 (the number zero) if none.
     */
    public function count(int $mode = COUNT_NORMAL): int {}

    /**
     * Delete a file within a phar archive
     * @param string $localName Path within an archive to the file to delete.
     * @return bool returns TRUE on success, but it is better to check for thrown exception, and assume success if none is thrown.
     * @throws \PharException Throws PharException if errors occur while flushing changes to disk.
     */
    public function delete(string $localName): bool {}

    /**
     * Deletes the global metadata of the phar
     * @return bool returns TRUE on success, but it is better to check for thrown exception, and assume success if none is thrown.
     * @throws \PharException Throws PharException if errors occur while flushing changes to disk.
     */
    public function delMetadata(): bool {}

    /**
     * (Unknown)
     *
     * Extract the contents of a phar archive to a directory
     * @param string $directory Path within an archive to the file to delete.
     * @param string|array|null $files [optional] The name of a file or directory to extract, or an array of files/directories to extract
     * @param bool $overwrite [optional] Set to TRUE to enable overwriting existing files
     * @return bool returns TRUE on success, but it is better to check for thrown exception, and assume success if none is thrown.
     * @throws \PharException Throws PharException if errors occur while flushing changes to disk.
     */
    public function extractTo(
        string $directory,
        array|string|null $files = null,
        bool $overwrite = false
    ): bool {}

    /**
     * Set the alias for the Phar archive
     * @param string $alias A shorthand string that this archive can be referred to in phar stream wrapper access.
     * @return bool
     * @throws \PharException Throws PharException on all method calls
     */
    public function setAlias(string $alias): bool {}

    /**
     * @return string|null
     * @see setAlias
     */
    public function getAlias(): ?string {}

    /**
     * Gets the path without filename
     * @return string the path to the file.
     * @since 5.3
     */
    public function getPath(): string {}

    /**
     * Returns phar archive meta-data
     * @param array $unserializeOptions [optional] if is set to anything other than the default, the resulting metadata won't be cached and this won't return the value from the cache
     * @return mixed any PHP variable that can be serialized and is stored as meta-data for the Phar archive, or NULL if no meta-data is stored.
     */
    public function getMetadata(array $unserializeOptions = []): mixed {}

    /**
     * Return whether phar was modified
     * @return bool TRUE if the phar has been modified since opened, FALSE if not.
     */
    public function getModified(): bool {}

    /**
     * Return MD5/SHA1/SHA256/SHA512/OpenSSL signature of a Phar archive
     * @return array Array with the opened archive's signature in hash key and MD5, SHA-1, SHA-256, SHA-512, or OpenSSL in hash_type. This signature is a hash calculated on the entire phar's contents, and may be used to verify the integrity of the archive. A valid signature is absolutely required of all ...
     */
    public function getSignature(): array|false {}

    /**
     * Return the PHP loader or bootstrap stub of a Phar archive
     * @return string a string containing the contents of the bootstrap loader (stub) of the current Phar archive.
     */
    public function getStub(): string {}

    /**
     * Return version info of Phar archive
     * @return string The opened archive's API version. This is not to be confused with the API version that the loaded phar extension will use to create new phars. Each Phar archive has the API version hard-coded into its manifest. See Phar file format documentation for more information.
     */
    public function getVersion(): string {}

    /**
     * Returns whether phar has global meta-data
     * @return bool TRUE if meta-data has been set, and FALSE if not.
     */
    public function hasMetadata(): bool {}

    /**
     * Used to determine whether Phar write operations are being buffered, or are flushing directly to disk
     * @return bool TRUE if the write operations are being buffer, FALSE otherwise.
     */
    public function isBuffering(): bool {}

    /**
     * Returns Phar::GZ or PHAR::BZ2 if the entire phar archive is compressed (.tar.gz/tar.bz and so on)
     * @return mixed Phar::GZ, Phar::BZ2 or FALSE
     */
    public function isCompressed(): int|false {}

    /**
     * Returns true if the phar archive is based on the tar/phar/zip file format depending on the parameter
     * @param int $format Either Phar::PHAR, Phar::TAR, or Phar::ZIP to test for the format of the archive.
     * @return bool TRUE if the phar archive matches the file format requested by the parameter
     */
    public function isFileFormat(int $format): bool {}

    /**
     * (Unknown)
     *
     * Returns true if the phar archive can be modified
     * @return bool TRUE if the phar archive can be modified
     */
    public function isWritable(): bool {}

    /**
     * (Unknown)
     *
     * Used to set the PHP loader or bootstrap stub of a Phar archive to the default loader
     * @param string $index [optional] Relative path within the phar archive to run if accessed on the command-line
     * @param string $webIndex [optional] Relative path within the phar archive to run if accessed through a web browser
     * @return bool TRUE on success or FALSE on failure.
     * @throws \PharException Throws PharException on all method calls
     */
    public function setDefaultStub(
        string|null $index = null,
        string|null $webIndex = null
    ): bool {}

    /**
     * Sets phar archive meta-data
     * @param mixed $metadata Any PHP variable containing information to store that describes the phar archive
     * @return void No value is returned.
     */
    public function setMetadata(mixed $metadata): void {}

    /**
     * set the signature algorithm for a phar and apply it.
     * @param int $algo One of Phar::MD5, Phar::SHA1, Phar::SHA256, Phar::SHA512, or Phar::OPENSSL
     * @param string $privateKey [optional] The contents of an OpenSSL private key, as extracted from a certificate or OpenSSL key file: $private = openssl_get_privatekey(file_get_contents('private.pem')); $pkey = ''; openssl_pkey_export($private, $pkey); $p->setSignatureAlgorithm(Phar::OPENSSL, $pkey); ...
     * @return void No value is returned.
     * @throws \UnexpectedValueException Throws UnexpectedValueException for many errors.
     * @throws \BadMethodCallException Throws BadMethodCallException if called for a zip- or a tar-based phar archive.
     * @throws \PharException Throws a PharException if any problems occur flushing changes to disk.
     */
    public function setSignatureAlgorithm(
        int $algo,
        string|null $privateKey = null
    ): void {}

    /**
     * Used to set the PHP loader or bootstrap stub of a Phar archive
     * @param string $stub A string or an open stream handle to use as the executable stub for this phar archive.
     * @param int $length [optional]
     * @return bool TRUE on success or FALSE on failure.
     * @throws \PharException Throws PharException on all method calls
     */
    public function setStub(
        $stub,
        int $length
    ): bool {}

    /**
     * Start buffering Phar write operations, do not modify the Phar object on disk
     * @return void No value is returned.
     */
    public function startBuffering(): void {}

    /**
     * Stop buffering write requests to the Phar archive, and save changes to disk
     * @return void No value is returned.
     */
    public function stopBuffering(): void {}

    /**
     * Returns the api version
     * @return string The API version string as in "1.0.0".
     */
    final public static function apiVersion(): string {}

    /**
     * Returns whether phar extension supports compression using either zlib or bzip2
     * @param int $compression [optional] Either Phar::GZ or Phar::BZ2 can be used to test whether compression is possible with a specific compression algorithm (zlib or bzip2).
     * @return bool TRUE if compression/decompression is available, FALSE if not.
     */
    final public static function canCompress(int $compression = 0): bool {}

    /**
     * Returns whether phar extension supports writing and creating phars
     * @return bool TRUE if write access is enabled, FALSE if it is disabled.
     */
    final public static function canWrite(): bool {}

    /**
     * (Unknown)
     *
     * Create a phar-file format specific stub
     * @param string|null $index [optional]
     * @param string|null $webIndex [optional]
     * @return string a string containing the contents of a customized bootstrap loader (stub) that allows the created Phar archive to work with or without the Phar extension enabled.
     */
    final public static function createDefaultStub(?string $index = null, ?string $webIndex = null): string {}

    /**
     * Return array of supported compression algorithms
     * @return string[] an array containing any of "GZ" or "BZ2", depending on the availability of the zlib extension or the bz2 extension.
     */
    final public static function getSupportedCompression(): array {}

    /**
     * Return array of supported signature types
     * @return string[] an array containing any of "MD5", "SHA-1", "SHA-256", "SHA-512", or "OpenSSL".
     */
    final public static function getSupportedSignatures(): array {}

    /**
     * instructs phar to intercept fopen, file_get_contents, opendir, and all of the stat-related functions
     * @return void
     */
    final public static function interceptFileFuncs(): void {}

    /**
     * Returns whether the given filename is a valid phar filename
     * @param string $filename The name or full path to a phar archive not yet created
     * @param bool $executable [optional] This parameter determines whether the filename should be treated as a phar executable archive, or a data non-executable archive
     * @return bool TRUE if the filename is valid, FALSE if not.
     */
    final public static function isValidPharFilename(string $filename, bool $executable = true): bool {}

    /**
     * Loads any phar archive with an alias
     * @param string $filename the full or relative path to the phar archive to open
     * @param string|null $alias [optional] The alias that may be used to refer to the phar archive. Note that many phar archives specify an explicit alias inside the phar archive, and a PharException will be thrown if a new alias is specified in this case.
     * @return bool TRUE on success or FALSE on failure.
     */
    final public static function loadPhar(string $filename, ?string $alias = null): bool {}

    /**
     * Reads the currently executed file (a phar) and registers its manifest
     * @param string|null $alias [optional] The alias that can be used in phar:// URLs to refer to this archive, rather than its full path.
     * @param int $offset [optional] Unused variable, here for compatibility with PEAR's PHP_Archive.
     * @return bool TRUE on success or FALSE on failure.
     */
    final public static function mapPhar(?string $alias = null, int $offset = 0): bool {}

    /**
     * Returns the full path on disk or full phar URL to the currently executing Phar archive
     * @param bool $returnPhar If FALSE, the full path on disk to the phar archive is returned. If TRUE, a full phar URL is returned.
     * @return string the filename if valid, empty string otherwise.
     */
    final public static function running(
        bool $returnPhar = true
    ): string {}

    /**
     * Mount an external path or file to a virtual location within the phar archive
     * @param string $pharPath The internal path within the phar archive to use as the mounted path location. This must be a relative path within the phar archive, and must not already exist.
     * @param string $externalPath A path or URL to an external file or directory to mount within the phar archive
     * @return void No return. PharException is thrown on failure.
     */
    final public static function mount(string $pharPath, string $externalPath): void {}

    /**
     * (Unknown)
     *
     * Defines a list of up to 4 $_SERVER variables that should be modified for execution
     * @param array $variables an array containing as string indices any of REQUEST_URI, PHP_SELF, SCRIPT_NAME and SCRIPT_FILENAME. Other values trigger an exception, and Phar::mungServer is case-sensitive.
     * @return void No return.
     */
    final public static function mungServer(array $variables): void {}

    /**
     * Completely remove a phar archive from disk and from memory
     * @param string $filename The path on disk to the phar archive.
     * @throws PharException
     * @return bool TRUE on success or FALSE on failure.
     */
    final public static function unlinkArchive(string $filename): bool {}

    /**
     * mapPhar for web-based phars. front controller for web applications
     * @param null|string $alias [optional] The alias that can be used in phar:// URLs to refer to this archive, rather than its full path.
     * @param string|null $index [optional] The location within the phar of the directory index.
     * @param null|string $fileNotFoundScript [optional] The location of the script to run when a file is not found. This script should output the proper HTTP 404 headers.
     * @param null|array $mimeTypes [optional] An array mapping additional file extensions to MIME type. If the default mapping is sufficient, pass an empty array. By default, these extensions are mapped to these MIME types: $mimes = array( 'phps' => Phar::PHPS, // pass to highlight_file() 'c' => ...
     * @param null|callable $rewrite [optional] The rewrites function is passed a string as its only parameter and must return a string or FALSE. If you are using fast-cgi or cgi then the parameter passed to the function is the value of the $_SERVER['PATH_INFO'] variable. Otherwise, the parameter passed ...
     * @return void No value is returned.
     */
    final public static function webPhar(
        ?string $alias = null,
        ?string $index = null,
        string|null $fileNotFoundScript = null,
        array $mimeTypes = [],
        ?callable $rewrite = null
    ): void {}

    /**
     * Seek to a DirectoryIterator item
     * @param int $offset The zero-based numeric position to seek to.
     * @return void No value is returned.
     */
    public function seek(int $offset): void {}

    /**
     * Destructs a non-executable tar or zip archive object
     */
    public function __destruct() {}
}
