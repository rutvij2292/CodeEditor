<?php

/**
 * DateTimeInterface was created so that parameter, return, or property type declarations may accept
 * either DateTimeImmutable or DateTime as a value. It is not possible to implement this interface
 * with userland classes.
 *
 * Common constants that allow for formatting DateTimeImmutable or DateTime objects through
 * DateTimeImmutable::format and DateTime::format are also defined on this interface.
 * @since 5.5
 */
interface DateTimeInterface
{
    /**
     * @since 7.2
     */
    public const ATOM = 'Y-m-d\TH:i:sP';

    /**
     * @since 7.2
     */
    public const COOKIE = 'l, d-M-Y H:i:s T';

    /**
     * This format is not compatible with ISO-8601, but is left this way for backward compatibility reasons.
     * Use DateTime::ATOM or DATE_ATOM for compatibility with ISO-8601 instead.
     * @since 7.2
     * @deprecated
     */
    public const ISO8601 = 'Y-m-d\TH:i:sO';

    /**
     * @since 8.2
     */
    public const ISO8601_EXPANDED = DATE_ISO8601_EXPANDED;

    /**
     * @since 7.2
     */
    public const RFC822 = 'D, d M y H:i:s O';

    /**
     * @since 7.2
     */
    public const RFC850 = 'l, d-M-y H:i:s T';

    /**
     * @since 7.2
     */
    public const RFC1036 = 'D, d M y H:i:s O';

    /**
     * @since 7.2
     */
    public const RFC1123 = 'D, d M Y H:i:s O';

    /**
     * @since 7.2
     */
    public const RFC2822 = 'D, d M Y H:i:s O';

    /**
     * @since 7.2
     */
    public const RFC3339 = 'Y-m-d\TH:i:sP';

    /**
     * @since 7.2
     */
    public const RFC3339_EXTENDED = 'Y-m-d\TH:i:s.vP';

    /**
     * @since 7.2
     */
    public const RFC7231 = 'D, d M Y H:i:s \G\M\T';

    /**
     * @since 7.2
     */
    public const RSS = 'D, d M Y H:i:s O';

    /**
     * @since 7.2
     */
    public const W3C = 'Y-m-d\TH:i:sP';

    /**
     * Returns the difference between two DateTime objects
     * @param DateTimeInterface $targetObject The date to compare to.
     * @param bool $absolute Should the interval be forced to be positive?
     * @return DateInterval The https://secure.php.net/manual/en/class.dateinterval.php DateInterval} object representing the difference between the two dates.
     */
    public function diff(
        DateTimeInterface $targetObject,
        bool $absolute = false
    ): DateInterval;

    /**
     * Returns date formatted according to given format
     * @param string $format Format accepted by  date().
     * @return string Returns the formatted date string on success. Prior to PHP 8.1, FALSE was returned on failure.
     */
    public function format(string $format): string;

    /**
     * Returns the timezone offset
     * @return int|false Returns the timezone offset in seconds from UTC on success. Prior to PHP 8.0, FALSE was returned on failure.
     */
    public function getOffset(): int;

    /**
     * Gets the Unix timestamp
     * @return int Returns the Unix timestamp representing the date.
     */
    public function getTimestamp(): int;

    /**
     * Return time zone relative to given DateTime
     * @return DateTimeZone|false Returns a DateTimeZone object on success or FALSE on failure.
     */
    public function getTimezone(): DateTimeZone|false;

    /**
     * The __wakeup handler
     * @return void Initializes a DateTime object.
     */
    public function __wakeup(): void;

    /**
     * Serialize a DateTime
     *
     * The __serialize() handler.
     * @return array The serialized representation of the DateTime object.
     */
    public function __serialize(): array;

    /**
     * Unserialize an Datetime
     *
     * The __unserialize() handler.
     * @param array $data The serialized DateTime.
     */
    public function __unserialize(array $data): void;

    /**
     * Gets the microsecond part of the Unix timestamp
     * @since 8.4
     */
    public function getMicrosecond(): int;
}
