<?php

/**
 * Representation of date and time.
 *
 * This class behaves the same as DateTime except new objects are returned when modification methods
 * such as DateTime::modify are called.
 * @since 5.5
 */
class DateTimeImmutable implements DateTimeInterface
{
    /**
     * @param string $datetime [optional] A date/time string. Valid formats are explained in Date and Time Formats. Enter 'now' here to obtain the current time when using the $timezone parameter.
     * @param null|DateTimeZone $timezone [optional] A DateTimeZone object representing the timezone of $datetime. If $timezone is omitted, the current timezone will be used. Note: The $timezone parameter and the current timezone are ignored when the $datetime parameter either is a UNIX timestamp (e.g. ...
     * @throws DateMalformedStringException Emits Exception in case of an error.
     */
    public function __construct(
        string $datetime = "now",
        DateTimeZone|null $timezone = null
    ) {}

    /**
     * Adds an amount of days, months, years, hours, minutes and seconds
     * @param DateInterval $interval A DateInterval object
     * @return static Returns a new DateTimeImmutable object with the modified data.
     */
    public function add(DateInterval $interval): static {}

    /**
     * Returns new DateTimeImmutable object formatted according to the specified format
     * @param string $format The format that the passed in string should be in. See the formatting options below. In most cases, the same letters as for the date can be used. All fields are initialised with the current date/time. In most cases you would want to reset these to "zero" (the Unix epoch, ...
     * @param string $datetime String representing the time.
     * @param null|DateTimeZone $timezone [optional]
     * @return DateTimeImmutable|false Returns a new DateTimeImmutable instance or false on failure.
     * @throws ValueError when the datetime contains NULL-bytes.
     */
    public static function createFromFormat(
        string $format,
        string $datetime,
        DateTimeZone|null $timezone = null
    ): DateTimeImmutable|false {}

    /**
     * Returns new DateTimeImmutable object encapsulating the given DateTime object
     * @param DateTime $object The mutable DateTime object that you want to convert to an immutable version. This object is not modified, but instead a new DateTimeImmutable object is created containing the same date time and timezone information.
     * @return DateTimeImmutable returns a new DateTimeImmutable instance.
     */
    public static function createFromMutable(DateTime $object): static {}

    /**
     * Returns the warnings and errors
     * @return array|false Returns array containing info about warnings and errors.
     */
    public static function getLastErrors(): array|false {}

    /**
     * Alters the timestamp
     * @param string $modifier A date/time string. Valid formats are explained in Date and Time Formats.
     * @return static|false Returns the newly created object or false on failure.
     * @throws DateMalformedStringException Returns the DateTimeImmutable object for method chaining or FALSE on failure.
     */
    public function modify(string $modifier): DateTimeImmutable|false {}

    /**
     * The __set_state handler
     * @param array $array Initialization array.
     * @return DateTimeImmutable Returns a new instance of a DateTimeImmutable object.
     */
    public static function __set_state(array $array): static {}

    /**
     * Sets the date
     * @param int $year Year of the date.
     * @param int $month Month of the date.
     * @param int $day Day of the date.
     * @return static Returns the DateTimeImmutable object for method chaining. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function setDate(
        int $year,
        int $month,
        int $day
    ): static {}

    /**
     * Sets the ISO date
     * @param int $year Year of the date.
     * @param int $week Week of the date.
     * @param int $dayOfWeek [optional] Offset from the first day of the week.
     * @return static Returns the DateTimeImmutable object for method chaining. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function setISODate(
        int $year,
        int $week,
        int $dayOfWeek = 1
    ): static {}

    /**
     * Sets the time
     * @param int $hour  Hour of the time.
     * @param int $minute  Minute of the time.
     * @param int $second [optional]  Second of the time.
     * @param int $microsecond [optional]  Microseconds of the time. Added since 7.1
     * @return static Returns the DateTimeImmutable object for method chaining. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function setTime(
        int $hour,
        int $minute,
        int $second = 0,
        int $microsecond = 0
    ): static {}

    /**
     * Sets the date and time based on an Unix timestamp
     * @param int $timestamp Unix timestamp representing the date.
     * @return static Returns the DateTimeImmutable object for method chaining. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function setTimestamp(int $timestamp): static {}

    /**
     * Sets the time zone
     * @param DateTimeZone $timezone A DateTimeZone object representing the desired time zone.
     * @return static Returns the DateTimeImmutable object for method chaining. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function setTimezone(DateTimeZone $timezone): static {}

    /**
     * Subtracts an amount of days, months, years, hours, minutes and seconds
     * @param DateInterval $interval A DateInterval object
     * @return static Returns a new DateTimeImmutable object with the modified data.
     * @throws DateInvalidOperationException Returns the DateTimeImmutable object for method chaining or FALSE on failure.
     */
    public function sub(DateInterval $interval): static {}

    /**
     * Returns the difference between two DateTime objects
     * @param DateTimeInterface $targetObject The date to compare to.
     * @param bool $absolute [optional] Should the interval be forced to be positive?
     * @return DateInterval The DateInterval object representing the difference between the two dates.
     */
    public function diff(
        DateTimeInterface $targetObject,
        bool $absolute = false
    ): DateInterval {}

    /**
     * Returns date formatted according to given format
     * @param string $format Format accepted by  date().
     * @return string Returns the formatted date string on success. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function format(string $format): string {}

    /**
     * Returns the timezone offset
     * @return int Returns the timezone offset in seconds from UTC on success. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function getOffset(): int {}

    /**
     * Gets the Unix timestamp
     * @return int Returns the Unix timestamp representing the date.
     */
    public function getTimestamp(): int {}

    /**
     * Return time zone relative to given DateTime
     * @return DateTimeZone|false Returns a DateTimeZone object on success or FALSE on failure.
     */
    public function getTimezone(): DateTimeZone|false {}

    /**
     * The __wakeup handler
     * @return void Initializes a DateTime object.
     */
    public function __wakeup(): void {}

    /**
     * Returns new DateTimeImmutable object encapsulating the given DateTimeInterface object
     * @param DateTimeInterface $object The DateTimeInterface object that needs to be converted to an immutable version. This object is not modified, but instead a new DateTimeImmutable object is created containing the same date, time, and timezone information.
     * @return static Returns a new DateTimeImmutable instance.
     * @since 8.0
     */
    public static function createFromInterface(DateTimeInterface $object): DateTimeImmutable {}

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
     *
     * Returns a new DateTimeImmutable object constructed from the old one, with modified
     * microsecond part.
     * @since 8.4
     * @throws \DateRangeError If the microsecond is outside the range [0, 999999], a DateRangeError is thrown.
     */
    public function setMicrosecond(int $microsecond): static {}
}
