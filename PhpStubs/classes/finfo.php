<?php

/**
 * This class provides an object-oriented interface into the fileinfo functions.
 */
class finfo
{
    /**
     * Alias of finfo_open
     *
     * This function is an alias of: finfo_open
     * @param int $flags [optional]
     * @param string $magic_database [optional]
     */
    public function __construct(
        int $flags = 0,
        string|null $magic_database = null
    ) {}

    /**
     * Set libmagic configuration options
     * @param int $flags One or disjunction of more Fileinfo constants.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function set_flags(int $flags): bool {}

    /**
     * Return information about a file
     * @param string $filename Name of a file to be checked.
     * @param int $flags [optional] One or disjunction of more Fileinfo constants.
     * @param resource $context [optional] For a description of contexts, refer to .
     * @return string|false a textual description of the contents of the filename argument, or FALSE if an error occurred.
     */
    public function file(
        string $filename,
        int $flags = FILEINFO_NONE,
        $context = null
    ): string|false {}

    /**
     * Return information about a string buffer
     * @param string $string Content of a file to be checked.
     * @param int $flags [optional] One or disjunction of more Fileinfo constants.
     * @param resource $context [optional]
     * @return string|false a textual description of the string argument, or FALSE if an error occurred.
     */
    public function buffer(
        string $string,
        int $flags = FILEINFO_NONE,
        $context = null
    ): string|false {}
}
