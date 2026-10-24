<?php

/**
 * MessageFormatter is a concrete class that enables users to produce concatenated, language-neutral
 * messages. The methods supplied in this class are used to build all the messages that are seen by
 * end users.
 *
 * The MessageFormatter class assembles messages from various fragments (such as text fragments,
 * numbers, and dates) supplied by the program. Because of the MessageFormatter class, the program
 * does not need to know the order of the fragments. The class uses the formatting specifications
 * for the fragments to assemble them into a message that is contained in a single string within a
 * resource bundle. For example, MessageFormatter enables you to print the phrase "Finished printing
 * x out of y ...
 */
class MessageFormatter
{
    /**
     * Constructs a new Message Formatter
     * @param string $locale The locale to use when formatting arguments
     * @param string $pattern The pattern string to stick arguments into. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
     * @throws IntlException on failure.
     */
    public function __construct(
        $locale,
        $pattern
    ) {}

    /**
     * Constructs a new Message Formatter
     * @param string $locale The locale to use when formatting arguments
     * @param string $pattern The pattern string to stick arguments into. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
     * @return MessageFormatter|null The formatter object
     */
    public static function create(
        $locale,
        $pattern
    ): ?MessageFormatter {}

    /**
     * Format the message
     * @param array $values Arguments to insert into the format string
     * @return string|false The formatted string, or FALSE if an error occurred
     */
    public function format(array $values): string|false {}

    /**
     * Quick format message
     * @param string $locale The locale to use for formatting locale-dependent parts
     * @param string $pattern The pattern string to insert things into. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
     * @param array $values The array of values to insert into the format string
     * @return string|false The formatted pattern string or FALSE if an error occurred
     */
    public static function formatMessage(
        $locale,
        $pattern,
        array $values
    ): string|false {}

    /**
     * Parse input string according to pattern
     * @param string $string The string to parse
     * @return array|false An array containing the items extracted, or FALSE on error
     */
    public function parse($string): array|false {}

    /**
     * Quick parse input string
     * @param string $locale The locale to use for parsing locale-dependent parts
     * @param string $pattern The pattern with which to parse the value.
     * @param string $message The string to parse, conforming to the pattern.
     * @return array|false An array containing items extracted, or FALSE on error
     */
    public static function parseMessage(
        $locale,
        $pattern,
        $message
    ): array|false {}

    /**
     * Set the pattern used by the formatter
     * @param string $pattern The pattern string to use in this message formatter. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setPattern($pattern): bool {}

    /**
     * Get the pattern used by the formatter
     * @return string|false The pattern string for this message formatter
     */
    public function getPattern(): string|false {}

    /**
     * Get the locale for which the formatter was created.
     * @return string The locale name
     */
    public function getLocale(): string {}

    /**
     * Get the error code from last operation
     * @return int The error code, one of UErrorCode values. Initial value is U_ZERO_ERROR.
     */
    public function getErrorCode(): int {}

    /**
     * Get the error text from the last operation
     * @return string Description of the last error.
     */
    public function getErrorMessage(): string {}
}
