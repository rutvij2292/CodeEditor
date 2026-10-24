<?php

/**
 * Representation of date and time.
 */
class DateTime implements DateTimeInterface
{
    /**
     * @removed 7.2
     */
    public const ATOM = 'Y-m-d\TH:i:sP';

    /**
     * @removed 7.2
     */
    public const COOKIE = 'l, d-M-Y H:i:s T';

    /**
     * @removed 7.2
     */
    public const ISO8601 = 'Y-m-d\TH:i:sO';

    /**
     * @removed 7.2
     */
    public const RFC822 = 'D, d M y H:i:s O';

    /**
     * @removed 7.2
     */
    public const RFC850 = 'l, d-M-y H:i:s T';

    /**
     * @removed 7.2
     */
    public const RFC1036 = 'D, d M y H:i:s O';

    /**
     * @removed 7.2
     */
    public const RFC1123 = 'D, d M Y H:i:s O';

    /**
     * @removed 7.2
     */
    public const RFC2822 = 'D, d M Y H:i:s O';

    /**
     * @removed 7.2
     */
    public const RFC3339 = 'Y-m-d\TH:i:sP';

    /**
     * @since 7.0
     * @removed 7.2
     */
    public const RFC3339_EXTENDED = 'Y-m-d\TH:i:s.vP';

    /**
     * @since 7.0
     * @removed 7.2
     */
    public const RFC7231 = 'D, d M Y H:i:s \G\M\T';

    /**
     * @removed 7.2
     */
    public const RSS = 'D, d M Y H:i:s O';

    /**
     * @removed 7.2
     */
    public const W3C = 'Y-m-d\TH:i:sP';

    /**
     * @param string $datetime [optional] A date/time string. Valid formats are explained in Date and Time Formats. Enter now here to obtain the current time when using the $timezone parameter.
     * @param null|DateTimeZone $timezone [optional] A DateTimeZone object representing the timezone of $datetime. If $timezone is omitted, the current timezone will be used. Note: The $timezone parameter and the current timezone are ignored when the $time parameter either is a UNIX timestamp (e.g. ...
     * @throws DateMalformedStringException Emits Exception in case of an error.
     */
    public function __construct(
        string $datetime = 'now',
        DateTimeZone|null $timezone = null
    ) {}

    /**
     * The __wakeup handler
     * @return void Initializes a DateTime object.
     */
    public function __wakeup(): void {}

    /**
     * Returns date formatted according to given format.
     * @param string $format The format of the outputted date string. See the formatting options below. There are also several predefined date constants that may be used instead, so for example DATE_RSS contains the format string 'D, d M Y H:i:s'. The following characters are recognized in the format ...
     * @return string Returns the formatted date string on success.
     */
    public function format(string $format): string {}

    /**
     * Alter the timestamp of a DateTime object by incrementing or decrementing
     * in a format accepted by strtotime().
     * @param string $modifier A date/time string. Valid formats are explained in Date and Time Formats.
     * @return static|false Returns the DateTime object for method chaining or FALSE on failure.
     * @throws DateMalformedStringException
     */
    public function modify(string $modifier): static|false {}

    /**
     * Adds an amount of days, months, years, hours, minutes and seconds to a DateTime object
     * @param DateInterval $interval A DateInterval object
     * @return static Returns the modified DateTime object for method chaining.
     */
    public function add(DateInterval $interval): DateTime {}

    /**
     * Returns new DateTime instance encapsulating the given DateTimeImmutable object
     * @param DateTimeImmutable $object The immutable DateTimeImmutable object that needs to be converted to a mutable version. This object is not modified, but instead a new DateTime instance is created containing the same date, time, and timezone information.
     * @return DateTime Returns a new DateTime instance.
     * @since 7.3
     */
    public static function createFromImmutable(DateTimeImmutable $object): static {}

    /**
     * Subtracts an amount of days, months, years, hours, minutes and seconds from a DateTime object
     * @param DateInterval $interval A DateInterval object
     * @return static Returns the modified DateTime object for method chaining.
     * @throws DateInvalidOperationException
     */
    public function sub(DateInterval $interval): DateTime {}

    /**
     * Get the TimeZone associated with the DateTime
     * @return DateTimeZone|false Returns a DateTimeZone object on success or false on failure.
     */
    public function getTimezone(): DateTimeZone|false {}

    /**
     * Set the TimeZone associated with the DateTime
     * @param DateTimeZone $timezone A DateTimeZone object representing the desired time zone.
     * @return static Returns the DateTime object for method chaining. The underlying point-in-time is not changed when calling this method.
     */
    public function setTimezone(DateTimeZone $timezone): DateTime {}

    /**
     * Returns the timezone offset
     * @return int Returns the timezone offset in seconds from UTC on success.
     */
    public function getOffset(): int {}

    /**
     * Sets the current time of the DateTime object to a different time.
     * @param int $hour Hour of the time.
     * @param int $minute Minute of the time.
     * @param int $second Second of the time.
     * @param int $microsecond Added since 7.1
     * @return static Returns the modified DateTime object for method chaining.
     */
    public function setTime(
        int $hour,
        int $minute,
        int $second = 0,
        int $microsecond = 0
    ): DateTime {}

    /**
     * Sets the current date of the DateTime object to a different date.
     * @param int $year Year of the date.
     * @param int $month Month of the date.
     * @param int $day Day of the date.
     * @return static Returns the modified DateTime object for method chaining.
     */
    public function setDate(
        int $year,
        int $month,
        int $day
    ): DateTime {}

    /**
     * Set a date according to the ISO 8601 standard - using weeks and day offsets rather than specific dates.
     * @param int $year Year of the date.
     * @param int $week Week of the date.
     * @param int $dayOfWeek Offset from the first day of the week.
     * @return static Returns the modified DateTime object for method chaining.
     */
    public function setISODate(
        int $year,
        int $week,
        int $dayOfWeek = 1
    ): DateTime {}

    /**
     * Sets the date and time based on a Unix timestamp.
     * @param int $timestamp Unix timestamp representing the date. Setting timestamps outside the range of integer is possible by using DateTimeImmutable::modify with the @ format.
     * @return static Returns the modified DateTime object for method chaining.
     */
    public function setTimestamp(int $timestamp): DateTime {}

    /**
     * Gets the Unix timestamp.
     * @return int Returns the Unix timestamp representing the date.
     */
    public function getTimestamp(): int {}

    /**
     * Returns the difference between two DateTime objects represented as a DateInterval.
     * @param DateTimeInterface $targetObject The date to compare to.
     * @param bool $absolute [optional] Whether to return absolute difference.
     * @return DateInterval The DateInterval object representing the difference between the two dates.
     */
    public function diff(
        DateTimeInterface $targetObject,
        bool $absolute = false
    ): DateInterval {}

    /**
     * Parse a string into a new DateTime object according to the specified format
     * @param string $format Format accepted by date().
     * @param string $datetime String representing the time.
     * @param null|DateTimeZone $timezone A DateTimeZone object representing the desired time zone.
     * @return DateTime|false Returns a new DateTime instance or false on failure.
     * @throws ValueError when the datetime contains NULL-bytes.
     */
    public static function createFromFormat(
        string $format,
        string $datetime,
        DateTimeZone|null $timezone = null
    ): DateTime|false {}

    /**
     * Returns an array of warnings and errors found while parsing a date/time string
     * @return array|false
     */
    public static function getLastErrors(): array|false {}

    /**
     * The __set_state handler
     * @param array $array Initialization array.
     * @return DateTime Returns a new instance of a DateTime object.
     */
    public static function __set_state(array $array): static {}

    /**
     * Returns new DateTime object encapsulating the given DateTimeInterface object
     * @param DateTimeInterface $object The DateTimeInterface object that needs to be converted to a mutable version. This object is not modified, but instead a new DateTime object is created containing the same date, time, and timezone information.
     * @return static Returns a new DateTime instance.
     * @since 8.0
     */
    public static function createFromInterface(DateTimeInterface $object): DateTime {}

    /**
     * Serialize a DateTime
     *
     * The __serialize() handler.
     * @return array The serialized representation of the DateTime object.
     */
    public function __serialize(): array {}

    /**
     * Unserialize an Datetime
     *
     * The __unserialize() handler.
     * @param array $data The serialized DateTime.
     */
    public function __unserialize(array $data): void {}

    /**
     * Creates an instance from a Unix timestamp
     * @since 8.4
     * @throws \DateRangeError If the timestamp is outside the range [PHP_INT_MIN, PHP_INT_MAX], a DateRangeError is thrown.
     */
    public static function createFromTimestamp(int|float $timestamp): static {}

    /**
     * Gets the microsecond part of the Unix timestamp
     * @since 8.4
     */
    public function getMicrosecond(): int {}

    /**
     * Sets microsecond part of the time
     * @since 8.4
     * @throws \DateRangeError If the microsecond is outside the range [0, 999999], a DateRangeError is thrown.
     */
    public function setMicrosecond(int $microsecond): static {}
}
