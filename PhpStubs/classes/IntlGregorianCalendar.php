<?php

/**
 * @since 5.5
 */
class IntlGregorianCalendar extends IntlCalendar
{
    /**
     * Create the Gregorian Calendar class
     * @param int $timezoneOrYear [optional]
     * @param int $localeOrMonth [optional]
     * @param int $day [optional]
     * @param int $hour [optional]
     * @param int $minute [optional]
     * @param int $second [optional]
     */
    public function __construct($timezoneOrYear, $localeOrMonth, $day, $hour, $minute, $second) {}

    /**
     * Set the Gregorian Calendar the change date
     * @param float $timestamp
     */
    public function setGregorianChange($timestamp): bool {}

    /**
     * Get the Gregorian Calendar change date
     * @return float
     */
    public function getGregorianChange(): float {}

    /**
     * Determine if the given year is a leap year
     * @param int $year
     * @return bool
     */
    public function isLeapYear($year): bool {}

    /**
     * Create a new IntlGregorianCalendar instance from date
     *
     * Creates a new IntlGregorianCalendar instance from date.
     * @since 8.3
     */
    public static function createFromDate(int $year, int $month, int $dayOfMonth): static {}

    /**
     * Create a new IntlGregorianCalendar instance from date and time
     *
     * Creates a new IntlGregorianCalendar instance from date and time.
     * @since 8.3
     */
    public static function createFromDateTime(int $year, int $month, int $dayOfMonth, int $hour, int $minute, ?int $second = null): static {}
}
