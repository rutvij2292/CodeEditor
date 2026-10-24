<?php

/**
 * Date Formatter is a concrete class that enables locale-dependent formatting/parsing of dates
 * using pattern strings and/or canned patterns.
 *
 * This class represents the ICU date formatting functionality. It allows users to display dates in
 * a localized format or to parse strings into PHP date values using pattern strings and/or canned
 * patterns.
 */
class IntlDateFormatter
{
    /**
     * Completely specified style (Tuesday, April 12, 1952 AD or 3:30:42pm PST)
     */
    public const FULL = 0;

    /**
     * Long style (January 12, 1952 or 3:30:32pm)
     */
    public const LONG = 1;

    /**
     * Medium style (Jan 12, 1952)
     */
    public const MEDIUM = 2;

    /**
     * Most abbreviated style, only essential data (12/13/52 or 3:30pm)
     */
    public const SHORT = 3;

    /**
     * Do not include this element
     */
    public const NONE = -1;

    /**
     * Gregorian Calendar
     */
    public const GREGORIAN = 1;

    /**
     * Non-Gregorian Calendar
     */
    public const TRADITIONAL = 0;

    public const RELATIVE_FULL = 128;

    public const RELATIVE_LONG = 129;

    public const RELATIVE_MEDIUM = 130;

    public const RELATIVE_SHORT = 131;

    public const PATTERN = -2;

    /**
     * Create a date formatter
     * @param string|null $locale Locale to use when formatting or parsing or null to use the value specified in the ini setting intl.default_locale.
     * @param int $dateType Format of the date determined by one of the IntlDateFormatter constants. The default value is IntlDateFormatter::FULL.
     * @param int $timeType Format of the time determined by one of the IntlDateFormatter constants. The default value is IntlDateFormatter::FULL.
     * @param mixed|null $timezone [optional]
     * @param mixed|null $calendar [optional]
     * @param string $pattern [optional]
     */
    public function __construct(
        $locale,
        $dateType,
        $timeType,
        int $dateType = 0,
        int $timeType = 0,
        $timezone = null,
        $calendar = null,
        $pattern = null
    ) {}

    /**
     * Create a date formatter
     * @param string $locale Locale to use when formatting or parsing; default is specified in the ini setting intl.default_locale.
     * @param int $dateType Date type to use (none, short, medium, long, full). This is one of the IntlDateFormatter constants.
     * @param int $timeType Time type to use (none, short, medium, long, full). This is one of the IntlDateFormatter constants.
     * @param string $timezone [optional] Time zone ID, default is system default.
     * @param int $calendar [optional] Calendar to use for formatting or parsing; default is Gregorian. This is one of the IntlDateFormatter calendar constants.
     * @param string $pattern [optional] Optional pattern to use when formatting or parsing. Possible patterns are documented at http://userguide.icu-project.org/formatparse/datetime.
     * @return IntlDateFormatter|null The created IntlDateFormatter or null in case of failure.
     */
    public static function create(
        $locale,
        $dateType,
        $timeType,
        int $dateType = 0,
        int $timeType = 0,
        $timezone = null,
        $calendar = null,
        $pattern = null
    ): ?IntlDateFormatter {}

    /**
     * Get the datetype used for the IntlDateFormatter
     * @return int|false The current date type value of the formatter.
     */
    public function getDateType(): int|false {}

    /**
     * Get the timetype used for the IntlDateFormatter
     * @return int|false The current date type value of the formatter.
     */
    public function getTimeType(): int|false {}

    /**
     * Get the calendar used for the IntlDateFormatter
     * @return int|false The calendar being used by the formatter.
     */
    public function getCalendar(): int|false {}

    /**
     * sets the calendar used to the appropriate calendar, which must be
     * @param int $calendar The calendar to use. Default is IntlDateFormatter::GREGORIAN.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setCalendar($calendar): bool {}

    /**
     * Get the timezone-id used for the IntlDateFormatter
     * @return string|false ID string for the time zone used by this formatter.
     */
    public function getTimeZoneId(): string|false {}

    /**
     * Get copy of formatter's calendar object
     * @return IntlCalendar|false|null A copy of the internal calendar object used by this formatter.
     */
    public function getCalendarObject(): IntlCalendar|false|null {}

    /**
     * Get formatter's timezone
     * @return IntlTimeZone|false The associated IntlTimeZone object or FALSE on failure.
     */
    public function getTimeZone(): IntlTimeZone|false {}

    /**
     * Sets the time zone to use
     * @param string $zone The time zone ID string of the time zone to use. If NULL or the empty string, the default time zone for the runtime is used.
     * @return bool TRUE on success or FALSE on failure.
     * @removed 7.0
     * @see IntlDateFormatter::setTimeZone()
     * @deprecated
     */
    public function setTimeZoneId($zone) {}

    /**
     * Sets formatter's timezone
     * @param mixed $timezone The timezone to use for this formatter. This can be specified in the following forms: NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() and as returned by ...
     * @return bool|null TRUE on success or FALSE on failure.
     */
    public function setTimeZone($timezone) {}

    /**
     * Set the pattern used for the IntlDateFormatter
     * @param string $pattern New pattern string to use. Possible patterns are documented at http://userguide.icu-project.org/formatparse/datetime.
     * @return bool TRUE on success or FALSE on failure. Bad formatstrings are usually the cause of the failure.
     */
    public function setPattern($pattern): bool {}

    /**
     * Get the pattern used for the IntlDateFormatter
     * @return string|false The pattern string being used to format/parse.
     */
    public function getPattern(): string|false {}

    /**
     * Get the locale used by formatter
     * @param int $type [optional]
     * @return string|false the locale of this formatter or 'false' if error
     */
    public function getLocale(
        $type = 0
    ): string|false {}

    /**
     * Set the leniency of the parser
     * @param bool $lenient Sets whether the parser is lenient or not, default is TRUE (lenient).
     * @return void Returns true on success or false on failure.
     */
    public function setLenient($lenient): void {}

    /**
     * Get the lenient used for the IntlDateFormatter
     * @return bool TRUE if parser is lenient, FALSE if parser is strict. By default the parser is lenient.
     */
    public function isLenient(): bool {}

    /**
     * Format the date/time value as a string
     * @param mixed $datetime Value to format. This may be a DateTime object, an integer representing a Unix timestamp value (seconds since epoch, UTC) or an array in the format output by localtime.
     * @return string|false The formatted string or, if an error occurred, FALSE.
     */
    public function format(
        $datetime = null,
        $datetime,
        $array = null
    ): string|false {}

    /**
     * Formats an object
     * @param object $datetime An object of type IntlCalendar or DateTime. The timezone information in the object will be used.
     * @param mixed $format [optional] How to format the date/time. This can either be an array with two elements (first the date style, then the time style, these being one of the constants IntlDateFormatter::NONE, IntlDateFormatter::SHORT, IntlDateFormatter::MEDIUM, IntlDateFormatter::LONG, ...
     * @param string|null $locale [optional] The locale to use, or NULL to use the default one.
     * @return string|false A string with result or FALSE on failure.
     */
    public static function formatObject($datetime, $format = null, $locale = null): string|false {}

    /**
     * Parse string to a timestamp value
     * @param string $string string to convert to a time
     * @param int &$offset [optional] Position at which to start the parsing in $value (zero-based). If no error occurs before $value is consumed, $parse_pos will contain -1 otherwise it will contain the position at which parsing ended (and the error occurred). This variable will contain the end position ...
     * @return int|float|false timestamp parsed value
     */
    public function parse($string, &$offset = null): int|float|false {}

    /**
     * Parse string to a field-based time value
     * @param string $string string to convert to a time
     * @param int &$offset [optional] Position at which to start the parsing in $value (zero-based). If no error occurs before $value is consumed, $parse_pos will contain -1 otherwise it will contain the position at which parsing ended . If $parse_pos > strlen($value), the parse fails immediately.
     * @return array|false Localtime compatible array of integers : contains 24 hour clock value in tm_hour field
     */
    public function localtime($string, &$offset = null): array|false {}

    /**
     * Get the error code from last operation
     * @return int The error code, one of UErrorCode values. Initial value is U_ZERO_ERROR.
     */
    public function getErrorCode(): int {}

    /**
     * Get the error text from the last operation.
     * @return string Description of the last error.
     */
    public function getErrorMessage(): string {}

    /**
     * Parse a string into a timestamp, updating an open calendar
     *
     * Converts string to an incremental time value, starting at offset and consuming as much of the
     * input value as possible.
     * @since 8.4
     */
    public function parseToCalendar(string $string, &$offset = null): int|float|false {}
}
