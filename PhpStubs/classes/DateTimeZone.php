<?php

/**
 * Representation of time zone
 */
class DateTimeZone
{
    public const AFRICA = 1;

    public const AMERICA = 2;

    public const ANTARCTICA = 4;

    public const ARCTIC = 8;

    public const ASIA = 16;

    public const ATLANTIC = 32;

    public const AUSTRALIA = 64;

    public const EUROPE = 128;

    public const INDIAN = 256;

    public const PACIFIC = 512;

    public const UTC = 1024;

    public const ALL = 2047;

    public const ALL_WITH_BC = 4095;

    public const PER_COUNTRY = 4096;

    /**
     * Creates new DateTimeZone object
     *
     * Creates a new DateTimeZone object.
     * @param string $timezone One of the supported timezone names, an offset value (+0200), or a timezone abbreviation (BST).
     * @throws DateInvalidTimeZoneException Emits Exception in case of an error.
     */
    public function __construct(string $timezone) {}

    /**
     * Returns the name of the timezone
     * @return string Depending on zone type, UTC offset (type 1), timezone abbreviation (type 2), and timezone identifiers as published in the IANA timezone database (type 3), the descriptor string to create a new DateTimeZone object with the same offset and/or rules. For example 02:00, CEST, or one of ...
     */
    public function getName(): string {}

    /**
     * Returns location information for a timezone
     * @return array|false Array containing location information about timezone or false on failure.
     */
    public function getLocation(): array|false {}

    /**
     * Returns the timezone offset from GMT
     * @param DateTimeInterface $datetime DateTime that contains the date/time to compute the offset from.
     * @return int Returns time zone offset in seconds.
     */
    public function getOffset(DateTimeInterface $datetime): int {}

    /**
     * Returns all transitions for the timezone
     * @param int $timestampBegin Begin timestamp.
     * @param int $timestampEnd End timestamp.
     * @return array|false Returns a numerically indexed array of transition arrays on success, or false on failure. DateTimeZone objects wrapping type 1 (UTC offsets) and type 2 (abbreviations) do not contain any transitions, and calling this method on them will return false. If timestampBegin is given, ...
     */
    public function getTransitions(
        int $timestampBegin = PHP_INT_MIN,
        int $timestampEnd = 2147483647
    ): array|false {}

    /**
     * Returns associative array containing dst, offset and the timezone name
     * @return array<string, list<array{dst: bool, offset: int, timezone_id: string|null}>> Returns the array of timezone abbreviations.
     */
    public static function listAbbreviations(): array {}

    /**
     * Returns a numerically indexed array with all timezone identifiers
     * @param int $timezoneGroup One of the DateTimeZone class constants (or a combination).
     * @param string $countryCode A two-letter (uppercase) ISO 3166-1 compatible country code. This option is only used when timezoneGroup is set to DateTimeZone::PER_COUNTRY.
     * @return array|false Returns the array of timezone identifiers, or FALSE on failure. Since PHP8, always returns array.
     */
    public static function listIdentifiers(
        int $timezoneGroup = DateTimeZone::ALL,
        string|null $countryCode = null
    ): array {}

    public function __wakeup(): void {}

    public static function __set_state(array $array): static {}

    public function __serialize(): array {}

    public function __unserialize(array $data): void {}
}
