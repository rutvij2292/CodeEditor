<?php

/**
 * Iterates through a file system in a similar fashion to
 * glob.
 */
class GlobIterator extends FilesystemIterator implements Countable
{
    /**
     * Construct a directory using glob
     * @param $pattern A glob pattern.
     * @param int $flags [optional]
     * @throws \UnexpectedValueException Throws an UnexpectedValueException if the directory does not exist.
     * @throws \ValueError Throws a ValueError if the directory is an empty string.
     */
    public function __construct(
        string $pattern,
        int $flags = FilesystemIterator::KEY_AS_PATHNAME|FilesystemIterator::CURRENT_AS_FILEINFO
    ) {}

    /**
     * Get the number of directories and files
     * @return int<0,max> The number of returned directories and files, as an integer.
     */
    public function count(): int {}
}
