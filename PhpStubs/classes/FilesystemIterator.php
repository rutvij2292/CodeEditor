<?php

/**
 * The Filesystem iterator
 */
class FilesystemIterator extends DirectoryIterator
{
    public const CURRENT_MODE_MASK = 240;

    public const CURRENT_AS_PATHNAME = 32;

    public const CURRENT_AS_FILEINFO = 0;

    public const CURRENT_AS_SELF = 16;

    public const KEY_MODE_MASK = 3840;

    public const KEY_AS_PATHNAME = 0;

    public const FOLLOW_SYMLINKS = 16384;

    public const KEY_AS_FILENAME = 256;

    public const NEW_CURRENT_AND_KEY = 256;

    public const SKIP_DOTS = 4096;

    public const UNIX_PATHS = 8192;

    public const OTHER_MODE_MASK = 28672;

    /**
     * Constructs a new filesystem iterator
     * @param string $directory The path of the filesystem item to be iterated over.
     * @param int $flags [optional]
     * @throws UnexpectedValueException if the path cannot be found.
     */
    public function __construct(
        string $directory,
        int $flags = FilesystemIterator::KEY_AS_PATHNAME|FilesystemIterator::CURRENT_AS_FILEINFO|FilesystemIterator::SKIP_DOTS
    ) {}

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
     * @return string|SplFileInfo|self The filename, file information, or $this depending on the set flags. See the FilesystemIterator constants.
     */
    public function current(): SplFileInfo|FilesystemIterator|string {}

    /**
     * Get the handling flags
     * @return int The integer value of the set flags.
     */
    public function getFlags(): int {}

    /**
     * Sets handling flags
     * @param int $flags The handling flags to set. See the FilesystemIterator constants.
     * @return void No value is returned.
     */
    public function setFlags(
        int $flags
    ): void {}
}
