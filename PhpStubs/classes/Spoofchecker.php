<?php

/**
 * This class is provided because Unicode contains large number of characters and incorporates the
 * varied writing systems of the world and their incorrect usage can expose programs or systems to
 * possible security attacks using characters similarity.
 *
 * Provided methods allow to check whether an individual string is likely an attempt at confusing
 * the reader (spoof detection), such as "pаypаl" spelled with Cyrillic 'а' characters.
 */
class Spoofchecker
{
    public const SINGLE_SCRIPT_CONFUSABLE = 1;

    public const MIXED_SCRIPT_CONFUSABLE = 2;

    public const WHOLE_SCRIPT_CONFUSABLE = 4;

    public const ANY_CASE = 8;

    public const SINGLE_SCRIPT = 16;

    public const INVISIBLE = 32;

    public const CHAR_LIMIT = 64;

    public const ASCII = 268435456;

    public const HIGHLY_RESTRICTIVE = 805306368;

    public const MODERATELY_RESTRICTIVE = 1073741824;

    public const MINIMALLY_RESTRICTIVE = 1342177280;

    public const UNRESTRICTIVE = 1610612736;

    public const SINGLE_SCRIPT_RESTRICTIVE = 536870912;

    public const MIXED_NUMBERS = 128;

    public const HIDDEN_OVERLAY = 256;

    /**
     * @since 8.4
     */
    public const IGNORE_SPACE = 1;

    /**
     * @since 8.4
     */
    public const CASE_INSENSITIVE = 2;

    /**
     * @since 8.4
     */
    public const ADD_CASE_MAPPINGS = 4;

    /**
     * @since 8.4
     */
    public const SIMPLE_CASE_INSENSITIVE = 6;

    /**
     * @since 8.6
     */
    public const LTR = 0;

    /**
     * @since 8.6
     */
    public const RTL = 1;

    /**
     * Constructor
     */
    public function __construct() {}

    /**
     * Checks if a given text contains any suspicious characters
     * @param string $string
     * @param string &$errorCode [optional]
     * @return bool Returns true if there are suspicious characters, false otherwise.
     */
    public function isSuspicious($string, &$errorCode = null): bool {}

    /**
     * Checks if a given text contains any confusable characters
     * @param string $string1
     * @param string $string2
     * @param int &$errorCode [optional]
     * @return bool Returns true if two given strings can be confused, false otherwise.
     */
    public function areConfusable(
        $string1,
        $string2,
        &$errorCode = null
    ): bool {}

    /**
     * Locales to use when running checks
     * @param string $locales
     * @return void
     */
    public function setAllowedLocales($locales): void {}

    /**
     * Set the checks to run
     * @param int $checks
     * @return void No value is returned.
     */
    public function setChecks($checks): void {}

    /**
     * Set the restriction level
     *
     * Sets the restriction level of SpoofChecker::isSuspicious.
     * @param int $level The restriction level of SpoofChecker::isSuspicious. One of Spoofchecker::ASCII, Spoofchecker::SINGLE_SCRIPT_RESTRICTIVE, Spoofchecker::HIGHLY_RESTRICTIVE, Spoofchecker::MODERATELY_RESTRICTIVE, Spoofchecker::MINIMALLY_RESTRICTIVE, or Spoofchecker::UNRESTRICTIVE. Defaults to ...
     */
    public function setRestrictionLevel($level): void {}

    /**
     * Set the set of characters allowed when running checks
     *
     * Restricts the characters that are considered acceptable by subsequent checks to the set
     * described by pattern. Any character outside of this set causes Spoofchecker::isSuspicious to
     * report a result.
     * @since 8.4
     * @throws \ValueError Throws a ValueError if pattern is not a valid character set pattern, or if patternOptions is not a valid combination of options.
     */
    public function setAllowedChars(string $pattern, int $patternOptions = 0): void {}

    /**
     * Gets the skeleton of the given string, used for confusability checks
     * @param string $string
     * @return string|false Returns the skeleton on success, or false on failure.
     * @since 8.6
     */
    public function getSkeleton(string $string): string|false {}

    /**
     * Gets the bidi skeleton of the given string, used for confusability checks
     * @param int $direction The paragraph direction, Spoofchecker::LTR or Spoofchecker::RTL.
     * @param string $string
     * @return string|false Returns the bidi skeleton on success, or false on failure.
     * @since 8.6
     */
    public function getBidiSkeleton(int $direction, string $string): string|false {}

    /**
     * Checks if two strings are confusable when displayed in the given paragraph direction
     * @param int $direction The paragraph direction, Spoofchecker::LTR or Spoofchecker::RTL.
     * @param string $string1
     * @param string $string2
     * @param int &$errorCode [optional]
     * @return bool Returns true if the two strings can be confused, false otherwise.
     * @since 8.6
     */
    public function areBidiConfusable(int $direction, string $string1, string $string2, &$errorCode = null): bool {}
}
