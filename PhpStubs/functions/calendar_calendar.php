<?php

/**
 * Converts Julian Day Count to Gregorian date
 * @param int $julian_day A julian day number as integer
 * @return string The gregorian date as a string in the form "month/day/year"
 */
function jdtogregorian(int $julian_day): string {}

/**
 * Converts a Gregorian date to Julian Day Count
 * @param int $month The month as a number from 1 (for January) to 12 (for December)
 * @param int $day The day as a number from 1 to 31
 * @param int $year The year as a number between -4714 and 9999
 * @return int The julian day for the given gregorian date as an integer.
 */
function gregoriantojd(int $month, int $day, int $year): int {}

/**
 * Converts a Julian Day Count to a Julian Calendar Date
 * @param int $julian_day A julian day number as integer
 * @return string The julian date as a string in the form "month/day/year"
 */
function jdtojulian(int $julian_day): string {}

/**
 * Converts a Julian Calendar date to Julian Day Count
 * @param int $month The month as a number from 1 (for January) to 12 (for December)
 * @param int $day The day as a number from 1 to 31
 * @param int $year The year as a number between -4713 and 9999
 * @return int The julian day for the given julian date as an integer.
 */
function juliantojd(int $month, int $day, int $year): int {}

/**
 * Converts a Julian day count to a Jewish calendar date
 * @param int $julian_day A julian day number as integer
 * @param bool $hebrew [optional] If the hebrew parameter is set to TRUE, the fl parameter is used for Hebrew, string based, output format.
 * @param int $flags [optional] The available formats are: CAL_JEWISH_ADD_ALAFIM_GERESH, CAL_JEWISH_ADD_ALAFIM, CAL_JEWISH_ADD_GERESHAYIM.
 * @return string The jewish date as a string in the form "month/day/year"
 */
function jdtojewish(int $julian_day, bool $hebrew = false, int $flags = 0): string {}

/**
 * Converts a date in the Jewish Calendar to Julian Day Count
 * @param int $month The month as a number from 1 to 13
 * @param int $day The day as a number from 1 to 30
 * @param int $year The year as a number between 1 and 9999
 * @return int The julian day for the given jewish date as an integer.
 */
function jewishtojd(int $month, int $day, int $year): int {}

/**
 * Converts a Julian Day Count to the French Republican Calendar
 * @param int $julian_day A julian day number as integer
 * @return string The french revolution date as a string in the form "month/day/year"
 */
function jdtofrench(int $julian_day): string {}

/**
 * Converts a date from the French Republican Calendar to a Julian Day Count
 * @param int $month The month as a number from 1 (for Vendémiaire) to 13 (for the period of 5-6 days at the end of each year)
 * @param int $day The day as a number from 1 to 30
 * @param int $year The year as a number between 1 and 14
 * @return int The julian day for the given french revolution date as an integer.
 */
function frenchtojd(int $month, int $day, int $year): int {}

/**
 * Returns the day of the week
 * @param int $julian_day A julian day number as integer
 * @param int $mode [optional] Calendar week modes Mode Meaning 0 (Default) Return the day number as an int (0=Sunday, 1=Monday, etc) 1 Returns string containing the day of week (English-Gregorian) 2 Return a string containing the abbreviated day of week (English-Gregorian)
 * @return string|int The gregorian weekday as either an integer or string.
 */
function jddayofweek(int $julian_day, int $mode = CAL_DOW_DAYNO): string|int {}

/**
 * Returns a month name
 * @param int $julian_day The Julian Day to operate on
 * @param int $mode The calendar mode (see table above).
 * @return string The month name for the given Julian Day and calendar.
 */
function jdmonthname(int $julian_day, int $mode): string {}

/**
 * Get Unix timestamp for midnight on Easter of a given year
 * @param int|null $year [optional] The year as a number between 1970 an 2037
 * @param int $mode [optional] Allows Easter dates to be calculated based on the Julian calendar when set to CAL_EASTER_ALWAYS_JULIAN
 * @return int The easter date as a unix timestamp.
 * @throws \ValueError A ValueError is thrown if the year is earlier than 1970 or later than 2037 when running on a 32-bit system, or later than 2,000,000,000 on a 64-bit system.
 */
function easter_date(?int $year = null, int $mode = CAL_EASTER_DEFAULT): int {}

/**
 * Get number of days after March 21 on which Easter falls for a given year
 * @param positive-int|null $year [optional] The year as a positive number
 * @param int $mode [optional] Allows to calculate easter dates based on the Gregorian calendar during the years 1582 - 1752 when set to CAL_EASTER_ROMAN. See the calendar constants for more valid constants.
 * @return int The number of days after March 21st that the Easter Sunday is in the given year.
 */
function easter_days(?int $year = null, int $mode = CAL_EASTER_DEFAULT): int {}

/**
 * Convert Unix timestamp to Julian Day
 * @param int|null $timestamp defaults to time() A unix timestamp to convert.
 * @return int|false A julian day number as integer.
 */
function unixtojd(?int $timestamp = null): int|false {}

/**
 * Convert Julian Day to Unix timestamp
 * @param int $julian_day A julian day number between 2440588 and 2465342.
 * @return int The unix timestamp for the start of the given julian day.
 * @throws \ValueError If julian_day is outside of the allowed range, a ValueError is thrown.
 */
function jdtounix(int $julian_day): int {}

/**
 * Converts from a supported calendar to Julian Day Count
 * @param int $calendar Calendar to convert from, one of CAL_GREGORIAN, CAL_JULIAN, CAL_JEWISH or CAL_FRENCH.
 * @param int $month The month as a number, the valid range depends on the calendar
 * @param int $day The day as a number, the valid range depends on the calendar
 * @param int $year The year as a number, the valid range depends on the calendar
 * @return int A Julian Day number.
 */
function cal_to_jd(int $calendar, int $month, int $day, int $year): int {}

/**
 * Converts from Julian Day Count to a supported calendar
 * @param int $julian_day Julian day as integer
 * @param int $calendar Calendar to convert to
 * @return array an array containing calendar information like month, day, year, day of week, abbreviated and full names of weekday and month and the date in string form "month/day/year".
 */
function cal_from_jd(int $julian_day, int $calendar): array {}

/**
 * Return the number of days in a month for a given year and calendar
 * @param int $calendar Calendar to use for calculation
 * @param int $month Month in the selected calendar
 * @param int $year Year in the selected calendar
 * @return int The length in days of the selected month in the given calendar
 */
function cal_days_in_month(int $calendar, int $month, int $year): int {}

/**
 * Returns information about a particular calendar
 * @param int $calendar [optional] Calendar to return information for. If no calendar is specified information about all calendars is returned.
 * @return array
 */
function cal_info(int $calendar = -1): array {}
