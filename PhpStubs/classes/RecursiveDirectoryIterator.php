<?php

/**
 * The RecursiveDirectoryIterator provides
 * an interface for iterating recursively over filesystem directories.
 */
class RecursiveDirectoryIterator extends FilesystemIterator implements RecursiveIterator
{
    /**
     * Constructs a RecursiveDirectoryIterator
     * @param string $directory The path of the directory to be iterated over.
     * @param int $flags [optional]
     * @throws UnexpectedValueException if the path cannot be found or is not a directory.
     * @since 5.1
     */
    public function __construct(
        string $directory,
        int $flags = FilesystemIterator::KEY_AS_PATHNAME|FilesystemIterator::CURRENT_AS_FILEINFO
    ) {}

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
     * Get sub path
     * @return string The sub path (sub directory).
     */
    public function getSubPath(): string {}

    /**
     * Get sub path and name
     * @return string The sub path (sub directory) and filename.
     */
    public function getSubPathname(): string {}

    /**
     * Rewinds back to the beginning
     * @return void
     */
    public function rewind(): void {}

    /**
     * Move to the next file
     * @return void
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
}
