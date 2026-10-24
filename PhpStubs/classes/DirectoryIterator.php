<?php

/**
 * The DirectoryIterator class provides a simple interface for viewing
 * the contents of filesystem directories.
 */
class DirectoryIterator extends SplFileInfo implements SeekableIterator
{
    /**
     * Constructs a new directory iterator from a path
     * @param string $directory The path of the directory to traverse.
     * @throws UnexpectedValueException if the path cannot be opened.
     * @throws RuntimeException if the path is an empty string.
     */
    public function __construct(string $directory) {}

    /**
     * Determine if current DirectoryIterator item is '.' or '..'
     * @return bool true if the entry is . or .., otherwise false
     */
    public function isDot(): bool {}

    /**
     * Rewind the DirectoryIterator back to the start
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Check whether current DirectoryIterator position is a valid file
     * @return bool true if the position is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Return the key for the current DirectoryIterator item
     * @return string The key for the current DirectoryIterator item.
     */
    public function key(): mixed {}

    /**
     * Return the current DirectoryIterator item.
     * @return DirectoryIterator The current DirectoryIterator item.
     */
    public function current(): mixed {}

    /**
     * Move forward to next DirectoryIterator item
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Seek to a DirectoryIterator item
     * @param int $offset The zero-based numeric position to seek to.
     * @return void No value is returned.
     */
    public function seek(int $offset): void {}
}
