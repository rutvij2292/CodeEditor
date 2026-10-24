<?php

/**
 * The SplFileObject class offers an object oriented interface for a file.
 */
class SplFileObject extends SplFileInfo implements RecursiveIterator, SeekableIterator
{
    /**
     * Drop newlines at the end of a line.
     */
    public const DROP_NEW_LINE = 1;

    /**
     * Read on rewind/next.
     */
    public const READ_AHEAD = 2;

    /**
     * Skip empty lines in the file. This requires the READ_AHEAD flag to work as expected.
     */
    public const SKIP_EMPTY = 4;

    /**
     * Read lines as CSV rows.
     */
    public const READ_CSV = 8;

    /**
     * Construct a new file object.
     * @param string $filename The file to open
     * @param string $mode [optional] The mode in which to open the file. See fopen for a list of allowed modes.
     * @param bool $useIncludePath [optional] Whether to search in the include_path for filename
     * @param resource $context [optional] A valid context resource created with stream_context_create
     * @throws RuntimeException When the filename cannot be opened
     * @throws LogicException When the filename is a directory
     */
    public function __construct(
        string $filename,
        string $mode = 'r',
        bool $useIncludePath = false,
        $context = null
    ) {}

    /**
     * Rewind the file to the first line
     * @return void No value is returned.
     * @throws RuntimeException If cannot be rewound
     */
    public function rewind(): void {}

    /**
     * Reached end of file
     * @return bool true if file is at EOF, false otherwise.
     */
    public function eof(): bool {}

    /**
     * Not at EOF
     * @return bool true if not reached EOF, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Gets line from file
     * @return string a string containing the next line from the file.
     * @throws RuntimeException If the file cannot be read
     */
    public function fgets(): string {}

    /**
     * Read from file
     * @param int $length The number of bytes to read.
     * @return string|false returns the string read from the file or FALSE on failure.
     * @since 5.5
     */
    public function fread(int $length): string|false {}

    /**
     * Gets line from file and parse as CSV fields
     * @param string $separator [optional] The field delimiter (one character only). Defaults as a comma or the value set using SplFileObject::setCsvControl.
     * @param string $enclosure [optional] The field enclosure character (one character only). Defaults as a double quotation mark or the value set using SplFileObject::setCsvControl.
     * @param string $escape [optional] The escape character (one character only). Defaults as a backslash (\) or the value set using SplFileObject::setCsvControl.
     * @return array|false|null an indexed array containing the fields read, or false on error. A blank line in a CSV file will be returned as an array comprising a single null field unless using SplFileObject::SKIP_EMPTY | SplFileObject::DROP_NEW_LINE, in which case empty lines are skipped.
     */
    public function fgetcsv(
        string $separator = ",",
        string $enclosure = "\"",
        string $escape = "\\"
    ): array|false {}

    /**
     * Write a field array as a CSV line
     * @param array $fields An array of values
     * @param string $separator [optional] The field delimiter (one character only). Defaults as a comma or the value set using SplFileObject::setCsvControl.
     * @param string $enclosure [optional] The field enclosure character (one character only). Defaults as a double quotation mark or the value set using SplFileObject::setCsvControl.
     * @param string $escape The optional escape parameter sets the escape character (one character only).
     * @param string $eol The optional eol parameter sets a custom End of Line sequence.
     * @return int|false Returns the length of the written string or FALSE on failure.
     * @since 5.4
     */
    public function fputcsv(
        array $fields,
        string $separator = ',',
        string $enclosure = '"',
        string $escape = "\\",
        string $eol = PHP_EOL
    ): int|false {}

    /**
     * Set the delimiter and enclosure character for CSV
     * @param string $separator [optional] The field delimiter (one character only).
     * @param string $enclosure [optional] The field enclosure character (one character only).
     * @param string $escape [optional] The field escape character (one character only).
     * @return void No value is returned.
     */
    public function setCsvControl(
        string $separator = ",",
        string $enclosure = "\"",
        string $escape = "\\"
    ): void {}

    /**
     * Get the delimiter and enclosure character for CSV
     * @return array an indexed array containing the delimiter and enclosure character.
     */
    public function getCsvControl(): array {}

    /**
     * Portable file locking
     * @param int $operation operation is one of the following: LOCK_SH to acquire a shared lock (reader).
     * @param int &$wouldBlock [optional] Set to 1 if the lock would block (EWOULDBLOCK errno condition).
     * @return bool true on success or false on failure.
     */
    public function flock(int $operation, &$wouldBlock = null): bool {}

    /**
     * Flushes the output to the file
     * @return bool true on success or false on failure.
     */
    public function fflush(): bool {}

    /**
     * Return current file position
     * @return int|false the position of the file pointer as an integer, or false on error.
     */
    public function ftell(): int|false {}

    /**
     * Seek to a position
     * @param int $offset The offset. A negative value can be used to move backwards through the file which is useful when SEEK_END is used as the whence value.
     * @param int $whence [optional] whence values are: SEEK_SET - Set position equal to offset bytes. SEEK_CUR - Set position to current location plus offset. SEEK_END - Set position to end-of-file plus offset. If whence is not specified, it is assumed to be SEEK_SET.
     * @return int 0 if the seek was successful, -1 otherwise. Note that seeking past EOF is not considered an error.
     */
    public function fseek(
        int $offset,
        int $whence = SEEK_SET
    ): int {}

    /**
     * Gets character from file
     * @return string|false a string containing a single character read from the file or false on EOF.
     */
    public function fgetc(): string|false {}

    /**
     * Output all remaining data on a file pointer
     * @return int the number of characters read from handle and passed through to the output.
     */
    public function fpassthru(): int {}

    /**
     * Gets line from file and strip HTML tags
     * @param string $allowable_tags [optional] You can use the optional third parameter to specify tags which should not be stripped.
     * @return string|false a string containing the next line of the file with HTML and PHP code stripped, or false on error.
     * @removed 8.0
     * @deprecated
     */
    public function fgetss($allowable_tags = null) {}

    /**
     * Parses input from file according to a format
     * @param string $format The specified format as described in the sprintf documentation.
     * @param mixed &...$vars [optional] The optional assigned values.
     * @return array|int|null If only one parameter is passed to this method, the values parsed will be returned as an array. Otherwise, if optional parameters are passed, the function will return the number of assigned values. The optional parameters must be passed by reference.
     */
    public function fscanf(
        string $format,
        mixed &...$vars
    ): array|int|null {}

    /**
     * Write to file
     * @param string $data The string to be written to the file.
     * @param int $length [optional] If the length argument is given, writing will stop after length bytes have been written or the end of string is reached, whichever comes first.
     * @return int|false the number of bytes written, or 0 (false since 7.4) on error.
     */
    public function fwrite(
        string $data,
        int $length = null
    ): int|false {}

    /**
     * Gets information about the file
     * @return array an array with the statistics of the file; the format of the array is described in detail on the stat manual page.
     */
    public function fstat(): array {}

    /**
     * Truncates the file to a given length
     * @param int $size The size to truncate to. If size is larger than the file it is extended with null bytes. If size is smaller than the file, the extra data will be lost.
     * @return bool true on success or false on failure.
     */
    public function ftruncate(int $size): bool {}

    /**
     * Retrieve current line of file
     * @return string|array|false Retrieves the current line of the file. If the SplFileObject::READ_CSV flag is set, this method returns an array containing the current line parsed as CSV data.
     */
    public function current(): string|array|false {}

    /**
     * Get line number
     * @return int the current line number.
     */
    public function key(): int {}

    /**
     * Read next line
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Sets flags for the SplFileObject
     * @param int $flags Bit mask of the flags to set. See SplFileObject constants for the available flags.
     * @return void No value is returned.
     */
    public function setFlags(int $flags): void {}

    /**
     * Gets flags for the SplFileObject
     * @return int an integer representing the flags.
     */
    public function getFlags(): int {}

    /**
     * Set maximum line length
     * @param int $maxLength The maximum length of a line.
     * @return void No value is returned.
     * @throws DomainException When maxLength is less than zero.
     */
    public function setMaxLineLen(int $maxLength): void {}

    /**
     * Get maximum line length
     * @return int<0, max> the maximum line length if one has been set with SplFileObject::setMaxLineLen, default is 0.
     */
    public function getMaxLineLen(): int {}

    /**
     * SplFileObject does not have children
     * @return bool false
     * @since 5.1
     */
    public function hasChildren(): false {}

    /**
     * No purpose
     * @return null|RecursiveIterator An SplFileObject does not have children so this method returns NULL.
     */
    public function getChildren(): null {}

    /**
     * Seek to specified line
     * @param int $line The zero-based line number to seek to.
     * @return void No value is returned.
     * @throws LogicException If the line is negative
     */
    public function seek(int $line): void {}

    /**
     * Alias of SplFileObject::fgets
     * @return string Returns a string containing the next line from the file.
     * @since 5.1
     */
    public function getCurrentLine(): string {}

    /**
     * Alias of SplFileObject::current
     */
    public function __toString(): string {}
}
