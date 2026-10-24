<?php

/**
 * @since 5.5
 */
class IntlTimeZone
{
    public const DISPLAY_SHORT = 1;

    public const DISPLAY_LONG = 2;

    public const DISPLAY_SHORT_GENERIC = 3;

    public const DISPLAY_LONG_GENERIC = 4;

    public const DISPLAY_SHORT_GMT = 5;

    public const DISPLAY_LONG_GMT = 6;

    public const DISPLAY_SHORT_COMMONLY_USED = 7;

    public const DISPLAY_GENERIC_LOCATION = 8;

    public const TYPE_ANY = 0;

    public const TYPE_CANONICAL = 1;

    public const TYPE_CANONICAL_LOCATION = 2;

    /**
     * Private constructor to disallow direct instantiation
     */
    private function __construct() {}

    /**
     * Get the number of IDs in the equivalency group that includes the given ID
     * @param string $timezoneId
     * @return int|false number of IDs or FALSE on failure
     */
    public static function countEquivalentIDs($timezoneId): int|false {}

    /**
     * Create a new copy of the default timezone for this host
     * @return IntlTimeZone
     */
    public static function createDefault(): IntlTimeZone {}

    /**
     * Get an enumeration over time zone IDs associated with the given country or offset
     * @param mixed $countryOrRawOffset [optional]
     * @return IntlIterator|false an iterator or FALSE on failure
     */
    public static function createEnumeration($countryOrRawOffset = null): IntlIterator|false {}

    /**
     * Create a timezone object for the given ID
     * @param string $timezoneId
     * @return IntlTimeZone|null a timezone object or NULL on failure
     */
    public static function createTimeZone($timezoneId): ?IntlTimeZone {}

    /**
     * Get an enumeration over system time zone IDs with the given filter conditions
     * @param int $type
     * @param string|null $region [optional]
     * @param int $rawOffset [optional]
     * @return IntlIterator|false an iterator or FALSE on failure
     */
    public static function createTimeZoneIDEnumeration(
        $type,
        $region = null,
        $rawOffset = null
    ): IntlIterator|false {}

    /**
     * Create a timezone object from DateTimeZone
     * @param DateTimeZone $timezone
     * @return IntlTimeZone|null a timezone object or NULL on failure
     */
    public static function fromDateTimeZone($timezone): ?IntlTimeZone {}

    /**
     * Get the canonical system timezone ID or the normalized custom time zone ID for the given time zone ID
     * @param string $timezoneId
     * @param bool &$isSystemId [optional]
     * @return string|false the timezone ID or FALSE on failure
     */
    public static function getCanonicalID($timezoneId, &$isSystemId = null): string|false {}

    /**
     * Get a name of this time zone suitable for presentation to the user
     * @param bool $dst [optional]
     * @param int $style [optional]
     * @param string $locale [optional]
     * @return string|false the timezone name or FALSE on failure
     */
    public function getDisplayName(
        $dst = false,
        $style = 2,
        $locale = null
    ): string|false {}

    /**
     * Get the amount of time to be added to local standard time to get local wall clock time
     * @return int
     */
    public function getDSTSavings(): int {}

    /**
     * Get an ID in the equivalency group that includes the given ID
     * @param string $timezoneId
     * @param int $offset
     * @return string|false the time zone ID or FALSE on failure
     */
    public static function getEquivalentID(
        $timezoneId,
        $offset
    ): string|false {}

    /**
     * Get last error code on the object
     * @return int|false
     */
    public function getErrorCode(): int|false {}

    /**
     * Get last error message on the object
     * @return string|false
     */
    public function getErrorMessage(): string|false {}

    /**
     * Create GMT (UTC) timezone
     * @return IntlTimeZone
     */
    public static function getGMT(): IntlTimeZone {}

    /**
     * Get timezone ID
     * @return string|false
     */
    public function getID(): string|false {}

    /**
     * Get the time zone raw and GMT offset for the given moment in time
     * @param float $timestamp moment in time for which to return offsets, in units of milliseconds from January 1, 1970 0:00 GMT, either GMT time or local wall time, depending on `local'.
     * @param bool $local if true, `date' is local wall time; otherwise it is in GMT time.
     * @param int &$rawOffset output parameter to receive the raw offset, that is, the offset not including DST adjustments
     * @param int &$dstOffset output parameter to receive the DST offset, that is, the offset to be added to `rawOffset' to obtain the total offset between local and GMT time. If DST is not in effect, this value is zero; otherwise it is a positive value, typically one hour.
     * @return bool boolean indication of success
     */
    public function getOffset(
        $timestamp,
        $local,
        &$rawOffset,
        &$dstOffset
    ): bool {}

    /**
     * Get the raw GMT offset (before taking daylight savings time into account
     * @return int
     */
    public function getRawOffset(): int {}

    /**
     * Get the region code associated with the given system time zone ID
     * @param string $timezoneId
     * @return string|false region or FALSE on failure
     */
    public static function getRegion($timezoneId): string|false {}

    /**
     * Get the timezone data version currently used by ICU
     * @return string|false
     */
    public static function getTZDataVersion(): string|false {}

    /**
     * Get the "unknown" time zone
     * @return IntlTimeZone
     */
    public static function getUnknown(): IntlTimeZone {}

    /**
     * Translates a system timezone (e.g. "America/Los_Angeles") into a Windows
     * timezone (e.g. "Pacific Standard Time").
     * @param string $timezoneId
     * @return string|false the Windows timezone or FALSE on failure
     * @since 7.1
     */
    public static function getWindowsID(string $timezoneId): string|false {}

    /**
     * Translate a Windows timezone into a system timezone
     *
     * Translates a Windows timezone (e.g. "Pacific Standard Time") into a system timezone (e.g.
     * "America/Los_Angeles").
     * @param string $timezoneId
     * @param string|null $region
     * @return string|false the Windows timezone or FALSE on failure
     * @since 7.1
     */
    public static function getIDForWindowsID(string $timezoneId, ?string $region = null): string|false {}

    /**
     * Check if this zone has the same rules and offset as another zone
     * @param IntlTimeZone $other
     * @return bool
     */
    public function hasSameRules(IntlTimeZone $other): bool {}

    /**
     * Convert to DateTimeZone object
     * @return DateTimeZone|false the DateTimeZone object or FALSE on failure
     */
    public function toDateTimeZone(): DateTimeZone|false {}

    /**
     * Check if this time zone uses daylight savings time
     * @return bool
     */
    public function useDaylightTime(): bool {}

    /**
     * Translate a timezone identifier to its IANA equivalent
     *
     * Translates a timezone identifier to its IANA equivalent. For example, "GMT" returns
     * "Etc/GMT", and "US/Eastern" returns "America/New_York".
     * @since 8.4
     */
    public static function getIanaID(string $timezoneId): string|false {}
}
