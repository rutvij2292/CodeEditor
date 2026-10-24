<?php

/**
 * @since 5.5
 */
class IntlCalendar
{
    public const FIELD_ERA = 0;

    public const FIELD_YEAR = 1;

    public const FIELD_MONTH = 2;

    public const FIELD_WEEK_OF_YEAR = 3;

    public const FIELD_WEEK_OF_MONTH = 4;

    public const FIELD_DATE = 5;

    public const FIELD_DAY_OF_YEAR = 6;

    public const FIELD_DAY_OF_WEEK = 7;

    public const FIELD_DAY_OF_WEEK_IN_MONTH = 8;

    public const FIELD_AM_PM = 9;

    public const FIELD_HOUR = 10;

    public const FIELD_HOUR_OF_DAY = 11;

    public const FIELD_MINUTE = 12;

    public const FIELD_SECOND = 13;

    public const FIELD_MILLISECOND = 14;

    public const FIELD_ZONE_OFFSET = 15;

    public const FIELD_DST_OFFSET = 16;

    public const FIELD_YEAR_WOY = 17;

    public const FIELD_DOW_LOCAL = 18;

    public const FIELD_EXTENDED_YEAR = 19;

    public const FIELD_JULIAN_DAY = 20;

    public const FIELD_MILLISECONDS_IN_DAY = 21;

    public const FIELD_IS_LEAP_MONTH = 22;

    public const FIELD_FIELD_COUNT = 24;

    public const FIELD_DAY_OF_MONTH = 5;

    public const DOW_SUNDAY = 1;

    public const DOW_MONDAY = 2;

    public const DOW_TUESDAY = 3;

    public const DOW_WEDNESDAY = 4;

    public const DOW_THURSDAY = 5;

    public const DOW_FRIDAY = 6;

    public const DOW_SATURDAY = 7;

    public const DOW_TYPE_WEEKDAY = 0;

    public const DOW_TYPE_WEEKEND = 1;

    public const DOW_TYPE_WEEKEND_OFFSET = 2;

    public const DOW_TYPE_WEEKEND_CEASE = 3;

    public const WALLTIME_FIRST = 1;

    public const WALLTIME_LAST = 0;

    public const WALLTIME_NEXT_VALID = 2;

    /**
     * Add a (signed) amount of time to a field
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @param int $value The signed amount to add to the current field. If the amount is positive, the instant will be moved forward; if it is negative, the instant wil be moved into the past. The unit is implicit to the field type. For instance, hours for IntlCalendar::FIELD_HOUR_OF_DAY.
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function add(
        $field,
        $value
    ): bool {}

    /**
     * Whether this object's time is after that of the passed object
     * https://secure.php.net/manual/en/intlcalendar.after.php
     * @param IntlCalendar $other The calendar whose time will be checked against this object's time.
     * @return bool Returns TRUE if this object's current time is after that of the calendar argument's time. Returns FALSE otherwise. Also returns FALSE on failure. You can use exceptions or intl_get_error_code() to detect error conditions.
     */
    public function after(IntlCalendar $other): bool {}

    /**
     * Whether this object's time is before that of the passed object
     * @param IntlCalendar $other  The calendar whose time will be checked against this object's time.
     * @return bool Returns TRUE</B> if this object's current time is before that of the calendar argument's time. Returns FALSE otherwise. Also returns FALSE on failure. You can use exceptions or intl_get_error_code() to detect error conditions.
     */
    public function before(IntlCalendar $other): bool {}

    /**
     * Clear a field or all fields
     * @param int $field [optional] One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return bool Returns TRUE on success or FALSE on failure. Failure can only occur is invalid arguments are provided.
     */
    public function clear($field = null) {}

    /**
     * Private constructor for disallowing instantiation
     */
    private function __construct() {}

    /**
     * Create a new IntlCalendar
     * @param mixed $timezone [optional] The timezone to use. NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() and as returned by date_default_timezone_get(). An IntlTimeZone, which will be used ...
     * @param string|null $locale [optional] A locale to use or NULL to use the default locale.
     * @return IntlCalendar|null The created IntlCalendar instance or NULL on failure.
     */
    public static function createInstance(
        $timezone = null,
        $locale = null
    ): ?IntlCalendar {}

    /**
     * Compare time of two IntlCalendar objects for equality
     * @param IntlCalendar $other The calendar to compare with the primary object.
     * @return bool Returns TRUE if the current time of both this and the passed in IntlCalendar object are the same, or FALSE otherwise. The value FALSE can also be returned on failure. This can only happen if bad arguments are passed in. In any case, the two cases can be distinguished by calling  ...
     */
    public function equals($other): bool {}

    /**
     * Calculate difference between given time and this object's time
     * @param float $timestamp The time against which to compare the quantity represented by the field. For the result to be positive, the time given for this parameter must be ahead of the time of the object the method is being invoked on.
     * @param int $field The field that represents the quantity being compared. One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false Returns a (signed) difference of time in the unit associated with the specified field or FALSE on failure.
     */
    public function fieldDifference(
        $timestamp,
        $field
    ): int|false {}

    /**
     * Create an IntlCalendar from a DateTime object or string
     * @param mixed $datetime A DateTime object or a string that can be passed to  DateTime::__construct().
     * @param $locale [optional]
     * @return IntlCalendar|null The created IntlCalendar object or NULL in case of failure. If a string is passed, any exception that occurs inside the DateTime constructor is propagated.
     */
    public static function fromDateTime(
        $datetime,
        $locale
    ): ?IntlCalendar {}

    /**
     * Get the value for a field
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An integer with the value of the time field.
     */
    public function get($field): int|false {}

    /**
     * The maximum value for a field, considering the object's current time
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing the maximum value in the units associated with the given field or FALSE on failure.
     */
    public function getActualMaximum($field): int|false {}

    /**
     * The minimum value for a field, considering the object's current time
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing the minimum value in the field's unit or FALSE on failure.
     */
    public function getActualMinimum($field): int|false {}

    /**
     * Get array of locales for which there is data
     * @return string[] An array of strings, one for which locale.
     */
    public static function getAvailableLocales(): array {}

    /**
     * Tell whether a day is a weekday, weekend or a day that has a transition between the two
     * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
     * @return int|false Returns one of the constants IntlCalendar::DOW_TYPE_WEEKDAY, IntlCalendar::DOW_TYPE_WEEKEND, IntlCalendar::DOW_TYPE_WEEKEND_OFFSET or IntlCalendar::DOW_TYPE_WEEKEND_CEASE or FALSE on failure.
     */
    public function getDayOfWeekType($dayOfWeek): int|false {}

    /**
     * Get last error code on the object
     * @return int|false An ICU error code indicating either success, failure or a warning.
     */
    public function getErrorCode(): int|false {}

    /**
     * Get last error message on the object
     * @return string|false The error message associated with last error that occurred in a function call on this object, or a string indicating the non-existance of an error.
     */
    public function getErrorMessage(): string|false {}

    /**
     * Get the first day of the week for the calendar's locale
     * @return int|false One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY or FALSE on failure.
     */
    public function getFirstDayOfWeek(): int|false {}

    /**
     * Get the largest local minimum value for a field
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing a field value, in the field's unit, or FALSE on failure.
     */
    public function getGreatestMinimum($field): int|false {}

    /**
     * Get set of locale keyword values
     * @param string $keyword The locale keyword for which relevant values are to be queried. Only 'calendar' is supported.
     * @param string $locale The locale onto which the keyword/value pair are to be appended.
     * @param bool $onlyCommon Whether to show only the values commonly used for the specified locale.
     * @return Iterator|false An iterator that yields strings with the locale keyword values or FALSE on failure.
     */
    public static function getKeywordValuesForLocale(
        $keyword,
        $locale,
        $onlyCommon
    ): IntlIterator|false {}

    /**
     * Get the smallest local maximum for a field
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing a field value in the field's unit or FALSE on failure.
     */
    public function getLeastMaximum($field): int|false {}

    /**
     * Get the locale associated with the object
     * @param int $type Whether to fetch the actual locale (the locale from which the calendar data originates, with Locale::ACTUAL_LOCALE) or the valid locale, i.e., the most specific locale supported by ICU relatively to the requested locale – see Locale::VALID_LOCALE. From the most general to the most ...
     * @return string|false A locale string or false on failure.
     */
    public function getLocale($type): string|false {}

    /**
     * Get the global maximum value for a field
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing a field value in the fieldʼs unit or false on failure.
     */
    public function getMaximum($field): int|false {}

    /**
     * Get minimal number of days the first week in a year or month can have
     * @return int|false An int representing a number of days or FALSE on failure.
     */
    public function getMinimalDaysInFirstWeek(): int|false {}

    /**
     * Get the global minimum value for a field
     * @param int $field One of the IntlCalendar date/time field. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return int|false An int representing a value for the given field in the field's unit or FALSE on failure.
     */
    public function getMinimum($field): int|false {}

    /**
     * Get number representing the current time
     * @return float A float representing a number of milliseconds since the epoch, not counting leap seconds.
     */
    public static function getNow(): float {}

    /**
     * Get behavior for handling repeating wall time
     * @return int One of the constants IntlCalendar::WALLTIME_FIRST or IntlCalendar::WALLTIME_LAST.
     */
    public function getRepeatedWallTimeOption(): int {}

    /**
     * Get behavior for handling skipped wall time
     * @return int One of the constants IntlCalendar::WALLTIME_FIRST, IntlCalendar::WALLTIME_LAST or IntlCalendar::WALLTIME_NEXT_VALID.
     */
    public function getSkippedWallTimeOption(): int {}

    /**
     * Get time currently represented by the object
     * @return float|false A float representing the number of milliseconds elapsed since the reference time (1 Jan 1970 00:00:00 UTC).
     */
    public function getTime(): float|false {}

    /**
     * Get the object's timezone
     * @return IntlTimeZone|false An IntlTimeZone object corresponding to the one used internally in this object.
     */
    public function getTimeZone(): IntlTimeZone|false {}

    /**
     * Get the calendar type
     * @return string A string representing the calendar type, such as 'gregorian', 'islamic', etc.
     */
    public function getType(): string {}

    /**
     * Get time of the day at which weekend begins or ends
     * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
     * @return int|false The number of milliseconds into the day at which the the weekend begins or ends or FALSE on failure.
     */
    public function getWeekendTransition($dayOfWeek): int|false {}

    /**
     * Whether the object's time is in Daylight Savings Time
     * @return bool Returns TRUE if the date is in Daylight Savings Time, FALSE otherwise. The value FALSE may also be returned on failure, for instance after specifying invalid field values on non-lenient mode; use exceptions or query intl_get_error_code() to disambiguate.
     */
    public function inDaylightTime(): bool {}

    /**
     * Whether another calendar is equal but for a different time
     * @param IntlCalendar $other The other calendar against which the comparison is to be made.
     * @return bool Assuming there are no argument errors, returns TRUE iif the calendars are equivalent except possibly for their set time.
     */
    public function isEquivalentTo(IntlCalendar $other): bool {}

    /**
     * Whether date/time interpretation is in lenient mode
     * @return bool A bool representing whether the calendar is set to lenient mode.
     */
    public function isLenient(): bool {}

    /**
     * Whether a certain date/time is in the weekend
     * @param float|null $timestamp [optional] An optional timestamp representing the number of milliseconds since the epoch, excluding leap seconds. If NULL, this object's current time is used instead.
     * @return bool A bool indicating whether the given or this object's time occurs in a weekend. The value FALSE may also be returned on failure, for instance after giving a date out of bounds on non-lenient mode; use exceptions or query intl_get_error_code() to disambiguate.
     */
    public function isWeekend($timestamp = null): bool {}

    /**
     * Add value to field without carrying into more significant fields
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @param mixed $value The (signed) amount to add to the field, TRUE for rolling up (adding 1), or FALSE for rolling down (subtracting 1).
     * @return bool Returns TRUE on success or FALSE on failure.
     */
    public function roll($field, $value): bool {}

    /**
     * Whether a field is set
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @return bool Assuming there are no argument errors, returns TRUE iif the field is set.
     */
    public function PS_UNRESERVE_PREFIX_isSet($field): bool {}

    /**
     * Set a time field or several common fields at once
     * @param int $year One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @param int $month The new value for IntlCalendar::FIELD_MONTH.
     * @param int $dayOfMonth [optional] The new value for IntlCalendar::FIELD_DAY_OF_MONTH. The month sequence is zero-based, i.e., January is represented by 0, February by 1, ..., December is 11 and Undecember (if the calendar has it) is 12.
     * @param int $hour [optional] The new value for IntlCalendar::FIELD_HOUR_OF_DAY.
     * @param int $minute [optional] The new value for IntlCalendar::FIELD_MINUTE.
     * @param int $second [optional] The new value for IntlCalendar::FIELD_SECOND.
     * @return bool Returns TRUE on success and FALSE on failure.
     */
    public function set(
        $year,
        $month,
        $dayOfMonth = null,
        $hour = null,
        $minute = null,
        $second = null
    ) {}

    /**
     * Set a time field or several common fields at once
     * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
     * @param int $value The new value of the given field.
     * @return bool Returns TRUE on success and FALSE on failure.
     * @since 5.5
     */
    public function set($field, $value) {}

    /**
     * Set the day on which the week is deemed to start
     * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
     * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
     */
    public function setFirstDayOfWeek($dayOfWeek) {}

    /**
     * Set whether date/time interpretation is to be lenient
     * @param bool $lenient Use TRUE to activate the lenient mode; FALSE otherwise.
     * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
     */
    public function setLenient($lenient) {}

    /**
     * Set behavior for handling repeating wall times at negative timezone offset transitions
     * @param int $option One of the constants IntlCalendar::WALLTIME_FIRST or IntlCalendar::WALLTIME_LAST.
     * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
     */
    public function setRepeatedWallTimeOption($option) {}

    /**
     * Set behavior for handling skipped wall times at positive timezone offset transitions
     * @param int $option One of the constants IntlCalendar::WALLTIME_FIRST, IntlCalendar::WALLTIME_LAST or IntlCalendar::WALLTIME_NEXT_VALID.
     * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
     */
    public function setSkippedWallTimeOption($option) {}

    /**
     * Set the calendar time in milliseconds since the epoch
     * @param float $timestamp An instant represented by the number of number of milliseconds between such instant and the epoch, ignoring leap seconds.
     * @return bool Returns TRUE on success and FALSE on failure.
     */
    public function setTime($timestamp): bool {}

    /**
     * Set the timezone used by this calendar
     * @param mixed $timezone The new timezone to be used by this calendar. It can be specified in the following ways: NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() and as returned by  ...
     * @return bool Returns TRUE on success and FALSE on failure.
     */
    public function setTimeZone($timezone): bool {}

    /**
     * Convert an IntlCalendar into a DateTime object
     * @return DateTime|false A DateTime object with the same timezone as this object (though using PHP's database instead of ICU's) and the same time, except for the smaller precision (second precision instead of millisecond). Returns FALSE on failure.
     */
    public function toDateTime(): DateTime|false {}

    /**
     * Set minimal number of days the first week in a year or month can have
     *
     * Sets the smallest number of days the first week of a year or month must have in the new year
     * or month. For instance, in the Gregorian calendar, if this value is 1, then the first week of
     * the year will necessarily include January 1st, while if this value is 7, then the week with
     * January 1st will be the first week of the year only if the day of the week for January 1st
     * matches the day of the week returned by IntlCalendar::getFirstDayOfWeek; otherwise it will be
     * the previous yearʼs last week.
     * @param int $days The number of minimal days to set.
     * @return bool Always returns true.
     * @throws \ValueError ValueError if days is out of range (less than 1 or more than 7).
     */
    public function setMinimalDaysInFirstWeek($days) {}

    /**
     * Set a date fields
     *
     * Sets a date fields to the given value.
     * @since 8.3
     */
    public function setDate(int $year, int $month, int $dayOfMonth): void {}

    /**
     * Set a date and time fields
     *
     * Sets a date and time fields to the given value.
     * @since 8.3
     */
    public function setDateTime(int $year, int $month, int $dayOfMonth, int $hour, int $minute, ?int $second = null): void {}
}
