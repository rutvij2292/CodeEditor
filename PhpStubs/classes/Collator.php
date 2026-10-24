<?php

/**
 * Provides string comparison capability with support for appropriate locale-sensitive sort
 * orderings.
 */
class Collator
{
    public const DEFAULT_VALUE = -1;

    public const PRIMARY = 0;

    public const SECONDARY = 1;

    public const TERTIARY = 2;

    public const DEFAULT_STRENGTH = 2;

    public const QUATERNARY = 3;

    public const IDENTICAL = 15;

    public const OFF = 16;

    public const ON = 17;

    public const SHIFTED = 20;

    public const NON_IGNORABLE = 21;

    public const LOWER_FIRST = 24;

    public const UPPER_FIRST = 25;

    /**
     * Sort strings with different accents from the back of the string. This
     * attribute is automatically set to
     * On
     * for the French locales and a few others. Users normally would not need
     * to explicitly set this attribute. There is a string comparison
     * performance cost when it is set On,
     * but sort key length is unaffected. Possible values are:
     * Collator::ON
     * Collator::OFF(default)
     * Collator::DEFAULT_VALUE
     *
     * FRENCH_COLLATION rules
     *
     * F=OFF cote < coté < côte < côté
     * F=ON cote < côte < coté < côté
     */
    public const FRENCH_COLLATION = 0;

    /**
     * The Alternate attribute is used to control the handling of the so called
     * variable characters in the UCA: whitespace, punctuation and symbols. If
     * Alternate is set to NonIgnorable
     * (N), then differences among these characters are of the same importance
     * as differences among letters. If Alternate is set to
     * Shifted
     * (S), then these characters are of only minor importance. The
     * Shifted value is often used in combination with
     * Strength
     * set to Quaternary. In such a case, whitespace, punctuation, and symbols
     * are considered when comparing strings, but only if all other aspects of
     * the strings (base letters, accents, and case) are identical. If
     * Alternate is not set to Shifted, then there is no difference ...
     */
    public const ALTERNATE_HANDLING = 1;

    /**
     * The Case_First attribute is used to control whether uppercase letters
     * come before lowercase letters or vice versa, in the absence of other
     * differences in the strings. The possible values are
     * Uppercase_First
     * (U) and Lowercase_First
     * (L), plus the standard Default
     * and Off.
     * There is almost no difference between the Off and Lowercase_First
     * options in terms of results, so typically users will not use
     * Lowercase_First: only Off or Uppercase_First. (People interested in the
     * detailed differences between X and L should consult the Collation
     * Customization). Specifying either L or U won't affect string comparison
     * performance, but will affect the sort key length.
     *
     * Possible values ...
     */
    public const CASE_FIRST = 2;

    /**
     * The Case_Level attribute is used when ignoring accents but not case. In
     * such a situation, set Strength to be Primary,
     * and Case_Level to be On.
     * In most locales, this setting is Off by default. There is a small
     * string comparison performance and sort key impact if this attribute is
     * set to be On.
     *
     * Possible values are:
     * Collator::OFF(default)
     * Collator::ON
     * Collator::DEFAULT_VALUE
     *
     * CASE_LEVEL rules
     *
     * S=1, E=X role = Role = rôle
     * S=1, E=O role = rôle < Role
     */
    public const CASE_LEVEL = 3;

    /**
     * The Normalization setting determines whether text is thoroughly
     * normalized or not in comparison. Even if the setting is off (which is
     * the default for many locales), text as represented in common usage will
     * compare correctly (for details, see UTN #5). Only if the accent marks
     * are in noncanonical order will there be a problem. If the setting is
     * On,
     * then the best results are guaranteed for all possible text input.
     * There is a medium string comparison performance cost if this attribute
     * is On,
     * depending on the frequency of sequences that require normalization.
     * There is no significant effect on sort key length. If the input text is
     * known to be in NFD or NFKD normalization forms, there is no need ...
     */
    public const NORMALIZATION_MODE = 4;

    /**
     * The ICU Collation Service supports many levels of comparison (named
     * "Levels", but also known as "Strengths"). Having these categories
     * enables ICU to sort strings precisely according to local conventions.
     * However, by allowing the levels to be selectively employed, searching
     * for a string in text can be performed with various matching conditions.
     * For more detailed information, see
     * collator_set_strength chapter.
     *
     * Possible values are:
     * Collator::PRIMARY
     * Collator::SECONDARY
     * Collator::TERTIARY(default)
     * Collator::QUATERNARY
     * Collator::IDENTICAL
     * Collator::DEFAULT_VALUE
     */
    public const STRENGTH = 5;

    /**
     * Compatibility with JIS x 4061 requires the introduction of an additional
     * level to distinguish Hiragana and Katakana characters. If compatibility
     * with that standard is required, then this attribute should be set
     * On,
     * and the strength set to Quaternary. This will affect sort key length
     * and string comparison string comparison performance.
     *
     * Possible values are:
     * Collator::OFF(default)
     * Collator::ON
     * Collator::DEFAULT_VALUE
     */
    public const HIRAGANA_QUATERNARY_MODE = 6;

    /**
     * When turned on, this attribute generates a collation key for the numeric
     * value of substrings of digits. This is a way to get '100' to sort AFTER
     * '2'.
     *
     * Possible values are:
     * Collator::OFF(default)
     * Collator::ON
     * Collator::DEFAULT_VALUE
     */
    public const NUMERIC_COLLATION = 7;

    public const SORT_REGULAR = 0;

    public const SORT_STRING = 1;

    public const SORT_NUMERIC = 2;

    /**
     * Create a collator
     * @param string $locale The locale whose collation rules should be used. Special values for locales can be passed in - if an empty string is passed for the locale, the default locale's collation rules will be used. If "root" is passed, UCA rules will be used. The locale attribute is typically the ...
     */
    public function __construct($locale) {}

    /**
     * Create a collator
     * @param string $locale The locale containing the required collation rules. Special values for locales can be passed in - if null is passed for the locale, the default locale collation rules will be used. If empty string ("") or "root" are passed, UCA rules will be used.
     * @return Collator|null Return new instance of Collator object, or NULL on error.
     */
    public static function create($locale): ?Collator {}

    /**
     * Compare two Unicode strings
     * @param string $string1 The first string to compare.
     * @param string $string2 The second string to compare.
     * @return int|false Return comparison result: 1 if str1 is greater than str2 ; 0 if str1 is equal to str2; -1 if str1 is less than str2 . On error boolean FALSE is returned.
     */
    public function compare(
        $string1,
        $string2
    ): int|false {}

    /**
     * Sort array using specified collator
     * @param string[] &$array Array of strings to sort.
     * @param int $flags [optional] Optional sorting type, one of the following: Collator::SORT_REGULAR - compare items normally (don't change types)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function sort(
        array &$array,
        $flags = 0
    ): bool {}

    /**
     * Sort array using specified collator and sort keys
     * @param string[] &$array Array of strings to sort
     * @return bool TRUE on success or FALSE on failure.
     */
    public function sortWithSortKeys(
        array &$array,
        $flags = []
    ): bool {}

    /**
     * Sort array maintaining index association
     * @param string[] &$array Array of strings to sort.
     * @param int $flags [optional] Optional sorting type, one of the following: Collator::SORT_REGULAR - compare items normally (don't change types)
     * @return bool TRUE on success or FALSE on failure.
     */
    public function asort(
        array &$array,
        $flags = 0
    ): bool {}

    /**
     * Get collation attribute value
     * @param int $attribute Attribute to get value for.
     * @return int|false Attribute value, or boolean FALSE on error.
     */
    public function getAttribute($attribute): int|false {}

    /**
     * Set collation attribute
     * @param int $attribute Attribute.
     * @param int $value Attribute value.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setAttribute(
        $attribute,
        $value
    ): bool {}

    /**
     * Get current collation strength
     * @return int current collation strength, or boolean FALSE on error.
     */
    public function getStrength(): int {}

    /**
     * Set collation strength
     * @param int $strength Strength to set. Possible values are: Collator::PRIMARY
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setStrength($strength) {}

    /**
     * Get collator's last error code
     * @return int|false Error code returned by the last Collator API function call.
     */
    public function getErrorCode(): int|false {}

    /**
     * Get the locale name of the collator
     * @param int $type You can choose between valid and actual locale ( Locale::VALID_LOCALE and Locale::ACTUAL_LOCALE, respectively).
     * @return string|false Real locale name from which the collation data comes. If the collator was instantiated from rules or an error occurred, returns boolean FALSE.
     */
    public function getLocale(
        $type
    ): string|false {}

    /**
     * Get text for collator's last error code
     * @return string|false Description of an error occurred in the last Collator API function call.
     */
    public function getErrorMessage(): string|false {}

    /**
     * Get sorting key for a string
     * @param string $string The string to produce the key from.
     * @return string|false the collation key for the string. Collation keys can be compared directly instead of strings.
     */
    public function getSortKey(
        $string,
        $arg2
    ): string|false {}
}
