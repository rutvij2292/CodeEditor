<?php

/**
 * Parse about any English textual datetime description into a Unix timestamp
 * @param string $datetime The string to parse. Before PHP 5.0.0, microseconds weren't allowed in the time, since PHP 5.0.0 they are allowed but ignored.
 * @param int|null $baseTimestamp [optional] Default value: null The timestamp which is used as a base for the calculation of relative dates.
 * @return int|false a timestamp on success, false otherwise. Previous to PHP 5.1.0, this function would return -1 on failure.
 */
function strtotime(string $datetime, ?int $baseTimestamp = null): int|false {}

/**
 * Format a local time/date
 * @param string $format The format of the outputted date string. See the formatting options below. There are also several predefined date constants that may be used instead, so for example DATE_RSS contains the format string 'D, d M Y H:i:s'. The following characters are recognized in the format ...
 * @param int|null $timestamp [optional] Default value: time(). The optional timestamp parameter is an integer Unix timestamp that defaults to the current local time if a timestamp is not given.
 * @return string|false a formatted date string. If a non-numeric value is used for timestamp, false is returned and an E_WARNING level error is emitted.
 */
function date(string $format, ?int $timestamp = null): string {}

/**
 * Format a local time/date as integer
 * @param string $format The following characters are recognized in the format parameter string format character Description B Swatch Beat/Internet Time d Day of the month h Hour (12 hour format) H Hour (24 hour format) i Minutes I (uppercase i) returns 1 if DST is activated, 0 otherwise L (uppercase ...
 * @param int|null $timestamp [optional] Default value: time(). The optional timestamp parameter is an integer Unix timestamp that defaults to the current local time if a timestamp is not given.
 * @return int|false an integer. As idate always returns an integer and as they can't start with a "0", idate may return fewer digits than you would expect. See the example below.
 */
function idate(string $format, ?int $timestamp = null): int|false {}

/**
 * Format a GMT/UTC date/time
 * @param string $format The format of the outputted date string. See the formatting options for the date function.
 * @param int|null $timestamp [optional] Default value: time(). The optional timestamp parameter is an integer Unix timestamp that defaults to the current local time if a timestamp is not given.
 * @return string|false a formatted date string. If a non-numeric value is used for timestamp, false is returned and an E_WARNING level error is emitted.
 */
function gmdate(string $format, ?int $timestamp = null): string {}

/**
 * Get Unix timestamp for a date
 * @param int $hour The number of the hour.
 * @param int|null $minute The number of the minute.
 * @param int|null $second The number of seconds past the minute.
 * @param int|null $month The number of the month.
 * @param int|null $day The number of the day.
 * @param int|null $year [optional] The number of the year, may be a two or four digit value, with values between 0-69 mapping to 2000-2069 and 70-100 to 1970-2000. On systems where time_t is a 32bit signed integer, as most common today, the valid range for year is somewhere between 1901 and 2038. ...
 * @param int $is_dst [optional] This parameter can be set to 1 if the time is during daylight savings time (DST), 0 if it is not, or -1 (the default) if it is unknown whether the time is within daylight savings time or not. If it's unknown, PHP tries to figure it out itself. This can cause unexpected ...
 * @return int|false mktime returns the Unix timestamp of the arguments given. If the arguments are invalid, the function returns false (before PHP 5.1 it returned -1).
 */
function mktime(
    int $hour,
    ?int $minute = null,
    ?int $second = null,
    ?int $month = null,
    ?int $day = null,
    ?int $year = null
): int|false {}

/**
 * Get Unix timestamp for a GMT date
 * @param int $hour The hour
 * @param int $minute The minute
 * @param int $second The second
 * @param int $month The month
 * @param int $day The day
 * @param int $year The year
 * @param int $is_dst Parameters always represent a GMT date so is_dst doesn't influence the result.
 * @return int|false a integer Unix timestamp.
 */
function gmmktime(
    int $hour,
    ?int $minute = null,
    ?int $second = null,
    ?int $month = null,
    ?int $day = null,
    ?int $year = null
): int|false {}

/**
 * Validate a Gregorian date
 * @param int $month The month is between 1 and 12 inclusive.
 * @param int $day The day is within the allowed number of days for the given month. Leap years are taken into consideration.
 * @param int $year The year is between 1 and 32767 inclusive.
 * @return bool true if the date given is valid; otherwise returns false.
 */
function checkdate(int $month, int $day, int $year): bool {}

/**
 * Format a local time/date according to locale settings
 * The following characters are recognized in the
 * format parameter string
 *
 * format
 * Description
 * Example returned values
 *
 * Day
 *
 * %a
 * An abbreviated textual representation of the day
 * Sun through Sat
 *
 * %A
 * A full textual representation of the day
 * Sunday through Saturday
 *
 * %d
 * Two-digit day of the month (with leading zeros)
 * 01 to 31
 *
 * %e
 * Day of the month, with a space preceding single digits
 * 1 to 31
 *
 * %j
 * Day of the year, 3 digits with leading zeros
 * 001 to 366
 *
 * %u
 * ISO-8601 numeric representation of the day of the week
 * 1 (for Monday) though 7 (for Sunday)
 *
 * %w
 * Numeric representation of the day of the week
 * 0 (for Sunday) through 6 (for ...
 * @param string $format The following characters are recognized in the format parameter string format Description Example returned values Day --- --- %a An abbreviated textual representation of the day Sun through Sat %A A full textual representation of the day Sunday through Saturday %d Two-digit ...
 * @param int|null $timestamp [optional] defaults to the value of time() Unix timestamp that defaults to the current local time if a timestamp is not given..
 * @return string|false a string formatted according format using the given timestamp or the current local time if no timestamp is given. Month and weekday names and other language-dependent strings respect the current locale set with setlocale.
 * @deprecated
 */
function strftime(string $format, ?int $timestamp = null): string|false {}

/**
 * Format a GMT/UTC time/date according to locale settings
 * @param string $format See description in strftime.
 * @param int|null $timestamp [optional]
 * @return string|false a string formatted according to the given format string using the given timestamp or the current local time if no timestamp is given. Month and weekday names and other language dependent strings respect the current locale set with setlocale.
 * @deprecated
 */
function gmstrftime(string $format, ?int $timestamp = null): string|false {}

/**
 * Return current Unix timestamp
 * @return int Returns the current time measured in the number of seconds since the Unix Epoch (January 1 1970 00:00:00 GMT).
 */
function time(): int {}

/**
 * Get the local time
 * @param int|null $timestamp [optional]
 * @param bool $associative [optional] If set to false or not supplied then the array is returned as a regular, numerically indexed array. If the argument is set to true then localtime returns an associative array containing all the different elements of the structure returned by the C function call ...
 * @return array If associative is set to false or not supplied then the array is returned as a regular, numerically indexed array. If associative is set to true then localtime returns an associative array containing the elements of the structure returned by the C function call to localtime. The keys ...
 */
function localtime(?int $timestamp = null, bool $associative = false): array {}

/**
 * Get date/time information
 * @param int|null $timestamp [optional]
 * @return array an associative array of information related to the timestamp. Elements from the returned associative array are as follows: Key elements of the returned associative array Key Description Example returned values "seconds" Numeric representation of seconds 0 to 59 "minutes" Numeric ...
 */
function getdate(?int $timestamp = null): array {}

/**
 * Returns new DateTime object
 * @param string $datetime [optional] String in a format accepted by strtotime.
 * @param DateTimeZone|null $timezone [optional] Time zone of the time.
 * @return DateTime|false DateTime object on success or false on failure.
 */
function date_create(string $datetime = 'now', ?DateTimeZone $timezone = null): DateTime|false {}

/**
 * Alias:
 * DateTimeImmutable::__construct
 * Returns new DateTimeImmutable object
 * @see DateTimeImmutable::__construct()
 * @param string $datetime [optional] String in a format accepted by strtotime.
 * @param DateTimeZone|null $timezone [optional] Time zone of the time.
 * @return DateTimeImmutable|false DateTime object on success or false on failure.
 */
function date_create_immutable(string $datetime = 'now', ?DateTimeZone $timezone = null): DateTimeImmutable|false {}

/**
 * Returns new DateTimeImmutable object formatted according to the specified format
 * @param string $format The format that the passed in string should be in. See the formatting options below. In most cases, the same letters as for the date can be used. All fields are initialised with the current date/time. In most cases you would want to reset these to "zero" (the Unix epoch, ...
 * @param string $datetime String representing the time.
 * @param DateTimeZone|null $timezone [optional]
 * @return DateTimeImmutable|false Returns a new DateTimeImmutable instance or false on failure.
 * @throws ValueError when the datetime contains NULL-bytes.
 */
function date_create_immutable_from_format(string $format, string $datetime, ?DateTimeZone $timezone = null): DateTimeImmutable|false {}

/**
 * Alias:
 * DateTime::createFromFormat
 * @param string $format Format accepted by  date(). If format does not contain the character ! then portions of the generated time which are not specified in format will be set to the current system time. If format contains the character !, then portions of the generated time not provided in format, ...
 * @param string $datetime String representing the time.
 * @param DateTimeZone|null $timezone [optional] A DateTimeZone object representing the desired time zone.
 * @return DateTime|false  Returns a new DateTime instance or FALSE on failure.
 * @throws ValueError when the datetime contains NULL-bytes.
 */
function date_create_from_format(string $format, string $datetime, ?DateTimeZone $timezone = null): DateTime|false {}

/**
 * Returns associative array with detailed info about given date
 * @param string $datetime Date in format accepted by strtotime.
 * @return array|false array with information about the parsed date on success or false on failure.
 */
function date_parse(string $datetime): array {}

/**
 * Get info about given date formatted according to the specified format
 * @param string $format Format accepted by date with some extras.
 * @param string $datetime String representing the date.
 * @return array associative array with detailed info about given date.
 * @throws \ValueError This functions throws ValueError when the datetime contains NULL-bytes.
 */
function date_parse_from_format(string $format, string $datetime): array {}

/**
 * Returns the warnings and errors
 * Alias:
 * DateTime::getLastErrors
 * @return array|false Returns array containing info about warnings and errors.
 */
function date_get_last_errors(): array|false {}

/**
 * Alias:
 * DateTime::format
 * @param DateTimeInterface $object Procedural style only: A DateTime object returned by date_create
 * @param string $format The format of the outputted date string. See the formatting options below. There are also several predefined date constants that may be used instead, so for example DATE_RSS contains the format string 'D, d M Y H:i:s'. The following characters are recognized in the format ...
 * @return string|false formatted date string on success or FALSE on failure.
 */
function date_format(DateTimeInterface $object, string $format): string {}

/**
 * Alter the timestamp of a DateTime object by incrementing or decrementing
 * in a format accepted by strtotime().
 * Alias:
 * DateTime::modify
 * @param DateTime $object A DateTime object returned by date_create(). The function modifies this object.
 * @param string $modifier A date/time string. Valid formats are explained in Date and Time Formats.
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_modify(DateTime $object, string $modifier): DateTime|false {}

/**
 * Alias:
 * DateTime::add
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create(). The function modifies this object.
 * @param DateInterval $interval A DateInterval object
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_add(DateTime $object, DateInterval $interval): DateTime {}

/**
 * Subtracts an amount of days, months, years, hours, minutes and seconds from a datetime object
 * Alias:
 * DateTime::sub
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create(). The function modifies this object.
 * @param DateInterval $interval A DateInterval object
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_sub(DateTime $object, DateInterval $interval): DateTime {}

/**
 * Alias:
 * DateTime::getTimezone
 * @param DateTimeInterface $object Procedural style only: A DateTime object returned by date_create()
 * @return DateTimeZone|false Returns a DateTimeZone object on success or FALSE on failure.
 */
function date_timezone_get(DateTimeInterface $object): DateTimeZone|false {}

/**
 * Sets the time zone for the datetime object
 * Alias:
 * DateTime::setTimezone
 * @param DateTime|DateTimeInterface $object A DateTime object returned by date_create(). The function modifies this object.
 * @param DateTimeZone $timezone A DateTimeZone object representing the desired time zone.
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_timezone_set(DateTime $object, DateTimeZone $timezone): DateTime {}

/**
 * Alias:
 * DateTime::getOffset
 * @param DateTimeInterface $object Procedural style only: A DateTime object returned by date_create()
 * @return int|false Returns the timezone offset in seconds from UTC on success or FALSE on failure.
 */
function date_offset_get(DateTimeInterface $object): int {}

/**
 * Returns the difference between two datetime objects
 * Alias:
 * DateTime::diff
 * @param DateTimeInterface $baseObject
 * @param DateTimeInterface $targetObject The date to compare to
 * @param bool $absolute [optional] Whether to return absolute difference.
 * @return DateInterval|false The DateInterval object representing the difference between the two dates or FALSE (for PHP < 8.0) on failure.
 */
function date_diff(DateTimeInterface $baseObject, DateTimeInterface $targetObject, bool $absolute = false): DateInterval {}

/**
 * Alias:
 * DateTime::setTime
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create. The function modifies this object.
 * @param int $hour Hour of the time.
 * @param int $minute Minute of the time.
 * @param int $second [optional]
 * @param int $microsecond [optional]
 * @return DateTime Returns the DateTime object for method chaining. Prior to PHP 8.0, FALSE was returned on failure.
 */
function date_time_set(
    DateTime $object,
    int $hour,
    int $minute,
    int $second = 0,
    int $microsecond = 0
): DateTime {}

/**
 * Alias:
 * DateTime::setDate
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create(). The function modifies this object.
 * @param int $year Year of the date.
 * @param int $month Month of the date.
 * @param int $day Day of the date.
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_date_set(DateTime $object, int $year, int $month, int $day): DateTime {}

/**
 * Alias:
 * DateTime::setISODate
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create. The function modifies this object.
 * @param int $year Year of the date
 * @param int $week Week of the date.
 * @param int $dayOfWeek [optional] Offset from the first day of the week.
 * @return DateTime|false Returns the DateTime object for method chaining or FALSE on failure.
 */
function date_isodate_set(DateTime $object, int $year, int $week, int $dayOfWeek = 1): DateTime {}

/**
 * Sets the date and time based on an unix timestamp
 * Alias:
 * DateTime::setTimestamp
 * @param DateTime $object Procedural style only: A DateTime object returned by date_create(). The function modifies this object.
 * @param int $timestamp Unix timestamp representing the date.
 * @return DateTime|false DateTime object for call chaining or FALSE on failure
 */
function date_timestamp_set(DateTime $object, int $timestamp): DateTime {}

/**
 * Gets the unix timestamp
 * Alias:
 * DateTime::getTimestamp
 * @param DateTimeInterface $object
 * @return int Returns the Unix timestamp representing the date.
 */
function date_timestamp_get(DateTimeInterface $object): int {}

/**
 * Returns new DateTimeZone object
 * @param string $timezone Time zone identifier as full name (e.g. Europe/Prague) or abbreviation (e.g. CET).
 * @return DateTimeZone|false DateTimeZone object on success or false on failure.
 */
function timezone_open(string $timezone): DateTimeZone|false {}

/**
 * Alias:
 * DateTimeZone::getName
 * @param DateTimeZone $object The DateTimeZone for which to get a name.
 * @return string One of the timezone names in the list of timezones.
 */
function timezone_name_get(DateTimeZone $object): string {}

/**
 * Returns the timezone name from abbreviation
 * @param string $abbr Time zone abbreviation.
 * @param int $utcOffset [optional] Offset from GMT in seconds. Defaults to -1 which means that first found time zone corresponding to abbr is returned. Otherwise exact offset is searched and only if not found then the first time zone with any offset is returned.
 * @param int $isDST [optional] Daylight saving time indicator. If abbr doesn't exist then the time zone is searched solely by offset and isdst.
 * @return string|false time zone name on success or false on failure.
 * @since 5.1
 */
function timezone_name_from_abbr(string $abbr, int $utcOffset = -1, int $isDST = -1): string|false {}

/**
 * Alias:
 * @param DateTimeZone $object Procedural style only: A DateTimeZone
 * @param DateTimeInterface $datetime DateTime that contains the date/time to compute the offset from.
 * @return int|false Returns time zone offset in seconds on success or FALSE on failure.
 */
function timezone_offset_get(DateTimeZone $object, DateTimeInterface $datetime): int {}

/**
 * Returns all transitions for the timezone
 * Alias:
 * DateTimeZone::getTransitions
 * @param DateTimeZone $object Procedural style only: A DateTimeZone object returned by timezone_open()
 * @param int $timestampBegin [optional] Begin timestamp
 * @param int $timestampEnd [optional] End timestamp
 * @return array|false Returns numerically indexed array containing associative array with all transitions on success or FALSE on failure.
 */
function timezone_transitions_get(DateTimeZone $object, int $timestampBegin = PHP_INT_MIN, int $timestampEnd = 2147483647): array|false {}

/**
 * Alias:
 * DateTimeZone::getLocation
 * @param DateTimeZone $object Procedural style only: A DateTimeZone object returned by timezone_open()
 * @return array|false Array containing location information about timezone.
 */
function timezone_location_get(DateTimeZone $object): array|false {}

/**
 * Returns a numerically indexed array containing all defined timezone identifiers
 * Alias:
 * DateTimeZone::listIdentifiers()
 * @param int $timezoneGroup [optional] One of DateTimeZone class constants.
 * @param string|null $countryCode [optional] A two-letter ISO 3166-1 compatible country code. Note: This option is only used when $timezoneGroup is set to DateTimeZone::PER_COUNTRY.
 * @return array|false Returns array on success or FALSE on failure.
 */
function timezone_identifiers_list(int $timezoneGroup = DateTimeZone::ALL, ?string $countryCode = null): array {}

/**
 * Returns associative array containing dst, offset and the timezone name
 * Alias:
 * DateTimeZone::listAbbreviations
 * @return array<string, list<array{dst: bool, offset: int, timezone_id: string|null}>>|false Array on success or FALSE on failure.
 */
function timezone_abbreviations_list(): array {}

/**
 * Gets the version of the timezonedb
 * @return string a string.
 */
function timezone_version_get(): string {}

/**
 * Alias:
 * DateInterval::createFromDateString
 * @param string $datetime A date with relative parts. Specifically, the relative formats supported by the parser used for strtotime() and DateTime will be used to construct the DateInterval.
 * @return DateInterval|false Returns a new DateInterval instance.
 */
function date_interval_create_from_date_string(string $datetime): DateInterval|false {}

/**
 * Alias:
 * DateInterval::format
 * @param DateInterval $object
 * @param string $format
 * @return string
 */
function date_interval_format(DateInterval $object, string $format): string {}

/**
 * Sets the default timezone used by all date/time functions in a script
 * @param string $timezoneId The timezone identifier, like UTC or Europe/Lisbon. The list of valid identifiers is available in the .
 * @return bool This function returns false if the timezone_identifier isn't valid, or true otherwise.
 */
function date_default_timezone_set(string $timezoneId): bool {}

/**
 * Gets the default timezone used by all date/time functions in a script
 * @return string a string.
 */
function date_default_timezone_get(): string {}

/**
 * Returns time of sunrise for a given day and location
 * @param int $timestamp The timestamp of the day from which the sunrise time is taken.
 * @param int $returnFormat [optional] format constants constant description example SUNFUNCS_RET_STRING returns the result as string 16:46 SUNFUNCS_RET_DOUBLE returns the result as float 16.78243132 SUNFUNCS_RET_TIMESTAMP returns the result as integer (timestamp) 1095034606
 * @param float|null $latitude [optional] Defaults to North, pass in a negative value for South. See also: date.default_latitude
 * @param float|null $longitude [optional] Defaults to East, pass in a negative value for West. See also: date.default_longitude
 * @param float|null $zenith [optional] Default: date.sunrise_zenith
 * @param float|null $utcOffset [optional]
 * @return string|int|float|false the sunrise time in a specified format on success or false on failure.
 * @deprecated in 8.1.  Use date_sun_info instead
 */
function date_sunrise(int $timestamp, int $returnFormat = SUNFUNCS_RET_STRING, ?float $latitude = null, ?float $longitude = null, ?float $zenith = null, ?float $utcOffset = null): string|int|float|false {}

/**
 * Returns time of sunset for a given day and location
 * @param int $timestamp The timestamp of the day from which the sunset time is taken.
 * @param int $returnFormat [optional] format constants constant description example SUNFUNCS_RET_STRING returns the result as string 16:46 SUNFUNCS_RET_DOUBLE returns the result as float 16.78243132 SUNFUNCS_RET_TIMESTAMP returns the result as integer (timestamp) 1095034606
 * @param float|null $latitude [optional] Defaults to North, pass in a negative value for South. See also: date.default_latitude
 * @param float|null $longitude [optional] Defaults to East, pass in a negative value for West. See also: date.default_longitude
 * @param float|null $zenith [optional] Default: date.sunset_zenith
 * @param float|null $utcOffset [optional]
 * @return string|int|float|false the sunset time in a specified format on success or false on failure.
 * @deprecated in 8.1.  Use date_sun_info instead
 */
function date_sunset(int $timestamp, int $returnFormat = SUNFUNCS_RET_STRING, ?float $latitude = null, ?float $longitude = null, ?float $zenith = null, ?float $utcOffset = null): string|int|float|false {}

/**
 * Returns an array with information about sunset/sunrise and twilight begin/end
 * @param int $timestamp Timestamp.
 * @param float $latitude Latitude in degrees.
 * @param float $longitude Longitude in degrees.
 * @return array{ sunrise: int|bool, sunset: int|bool, transit: int|bool, civil_twilight_begin: int|bool, civil_twilight_end: int|bool, nautical_twilight_begin: int|bool, nautical_twilight_end: int|bool, astronomical_twilight_begin: int|bool, astronomical_twilight_end: int|bool, }|false Returns array ...
 * @since 5.1
 */
function date_sun_info(int $timestamp, float $latitude, float $longitude): array {}
