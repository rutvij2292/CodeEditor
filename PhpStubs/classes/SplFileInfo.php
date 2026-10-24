<?php

/**
 * The SplFileInfo class offers a high-level object oriented interface to
 * information for an individual file.
 */
class SplFileInfo implements Stringable
{
    /**
     * Construct a new SplFileInfo object
     * @param string $filename Path to the file.
     * @since 5.1
     */
    public function __construct(string $filename) {}

    /**
     * Gets the path without filename
     * @return string the path to the file.
     * @since 5.1
     */
    public function getPath(): string {}

    /**
     * Gets the filename
     * @return string The filename.
     * @since 5.1
     */
    public function getFilename(): string {}

    /**
     * Gets the file extension
     * @return string a string containing the file extension, or an empty string if the file has no extension.
     * @since 5.3
     */
    public function getExtension(): string {}

    /**
     * Gets the base name of the file
     * @param string $suffix [optional] Optional suffix to omit from the base name returned.
     * @return string the base name without path information.
     * @since 5.2
     */
    public function getBasename(string $suffix = ''): string {}

    /**
     * Gets the path to the file
     * @return string The path to the file.
     * @since 5.1
     */
    public function getPathname(): string {}

    /**
     * Gets file permissions
     * @return int|false The file permissions on success, or FALSE on failure.
     * @since 5.1
     */
    public function getPerms(): int|false {}

    /**
     * Gets the inode for the file
     * @return int|false The inode number for the filesystem object on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getInode(): int|false {}

    /**
     * Gets file size
     * @return int|false The filesize in bytes on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getSize(): int|false {}

    /**
     * Gets the owner of the file
     * @return int|false The owner id in numerical format on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getOwner(): int|false {}

    /**
     * Gets the file group
     * @return int|false The group id in numerical format on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getGroup(): int|false {}

    /**
     * Gets last access time of the file
     * @return int|false The time the file was last accessed on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getATime(): int|false {}

    /**
     * Gets the last modified time
     * @return int|false The last modified time for the file, in a Unix timestamp on success, or FALSE on failure.
     * @since 5.1
     */
    public function getMTime(): int|false {}

    /**
     * Gets the inode change time
     * @return int|false The last change time, in a Unix timestamp on success, or FALSE on failure.
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getCTime(): int|false {}

    /**
     * Gets file type
     * @return string|false A string representing the type of the entry. May be one of file, link, dir, block, fifo, char, socket, or unknown, or FALSE on failure. May be one of file, link, or dir
     * @since 5.1
     * @throws \RuntimeException on error.
     */
    public function getType(): string|false {}

    /**
     * Tells if the entry is writable
     * @return bool true if writable, false otherwise;
     * @since 5.1
     */
    public function isWritable(): bool {}

    /**
     * Tells if file is readable
     * @return bool true if readable, false otherwise.
     * @since 5.1
     */
    public function isReadable(): bool {}

    /**
     * Tells if the file is executable
     * @return bool true if executable, false otherwise.
     * @since 5.1
     */
    public function isExecutable(): bool {}

    /**
     * Tells if the object references a regular file
     * @return bool true if the file exists and is a regular file (not a link), false otherwise.
     * @since 5.1
     */
    public function isFile(): bool {}

    /**
     * Tells if the file is a directory
     * @return bool true if a directory, false otherwise.
     * @since 5.1
     */
    public function isDir(): bool {}

    /**
     * Tells if the file is a link
     * @return bool true if the file is a link, false otherwise.
     * @since 5.1
     */
    public function isLink(): bool {}

    /**
     * Gets the target of a link
     * @return string|false The target of the filesystem link on success, or FALSE on failure.
     * @since 5.2
     * @throws \RuntimeException on error.
     */
    public function getLinkTarget(): string|false {}

    /**
     * Gets absolute path to file
     * @return string|false the path to the file, or FALSE if the file does not exist.
     * @since 5.2
     */
    public function getRealPath(): string|false {}

    /**
     * Gets an SplFileInfo object for the file
     * @template T of SplFileInfo
     * @param class-string<T> $class [optional] Name of an SplFileInfo derived class to use.
     * @return T An SplFileInfo object created for the file.
     * @since 5.1
     */
    public function getFileInfo(string|null $class = null): SplFileInfo {}

    /**
     * Gets an SplFileInfo object for the path
     * @template T of SplFileInfo
     * @param class-string<T> $class [optional] Name of an SplFileInfo derived class to use.
     * @return T|null A SplFileInfo object for the parent path of the file on success, or NULL on failure.
     * @since 5.1
     */
    public function getPathInfo(string|null $class = null): ?SplFileInfo {}

    /**
     * Gets an SplFileObject object for the file
     * @param string $mode [optional] The mode for opening the file. See the fopen documentation for descriptions of possible modes. The default is read only.
     * @param bool $useIncludePath [optional]
     * @param resource $context [optional]
     * @return SplFileObject The opened file as an SplFileObject object.
     * @since 5.1
     * @throws \RuntimeException If the file cannot be opened (e.g. insufficient access rights).
     */
    public function openFile(
        string $mode = 'r',
        bool $useIncludePath = false,
        $context = null
    ): SplFileObject {}

    /**
     * Sets the class name used with SplFileInfo::openFile
     * @template T of SplFileObject
     * @param class-string<T> $class [optional] The class name to use when openFile() is called.
     * @return void No value is returned.
     * @since 5.1
     */
    public function setFileClass(string $class = SplFileObject::class): void {}

    /**
     * Sets the class used with getFileInfo and getPathInfo
     * @template T of SplFileInfo
     * @param class-string<T> $class [optional] The class name to use.
     * @return void No value is returned.
     * @since 5.1
     */
    public function setInfoClass(string $class = SplFileInfo::class): void {}

    /**
     * Returns the path to the file as a string
     * @return string the path to the file.
     * @since 5.1
     */
    public function __toString(): string {}

    /**
     * @deprecated 8.2
     */
    final public function _bad_state_ex(): void {}

    public function __wakeup() {}

    /**
     * @return array
     * @since 7.4
     */
    public function __debugInfo(): array {}
}
