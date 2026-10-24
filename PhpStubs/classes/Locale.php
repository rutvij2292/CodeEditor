<?php

/**
 * A "Locale" is an identifier used to get language, culture, or regionally-specific behavior from
 * an API. PHP locales are organized and identified the same way that the CLDR locales used by ICU
 * (and many vendors of Unix-like operating systems, the Mac, Java, and so forth) use. Locales are
 * identified using RFC 4646 language tags (which use hyphen, not underscore) in addition to the
 * more traditional underscore-using identifiers. Unless otherwise noted the functions in this class
 * are tolerant of both formats.
 *
 * Examples of identifiers include: en-US (English, United States) zh-Hant-TW (Chinese, Traditional
 * Script, Taiwan) fr-CA, fr-FR (French for Canada and France respectively) The Locale class ...
 */
class Locale
{
    /**
     * This is locale the data actually comes from.
     */
    public const ACTUAL_LOCALE = 0;

    /**
     * This is the most specific locale supported by ICU.
     */
    public const VALID_LOCALE = 1;

    /**
     * Used as locale parameter with the methods of the various locale affected classes,
     * such as NumberFormatter. This constant would make the methods to use default
     * locale.
     */
    public const DEFAULT_LOCALE = null;

    /**
     * Language subtag
     */
    public const LANG_TAG = "language";

    /**
     * Extended language subtag
     */
    public const EXTLANG_TAG = "extlang";

    /**
     * Script subtag
     */
    public const SCRIPT_TAG = "script";

    /**
     * Region subtag
     */
    public const REGION_TAG = "region";

    /**
     * Variant subtag
     */
    public const VARIANT_TAG = "variant";

    /**
     * Grandfathered Language subtag
     */
    public const GRANDFATHERED_LANG_TAG = "grandfathered";

    /**
     * Private subtag
     */
    public const PRIVATE_TAG = "private";

    /**
     * Gets the default locale value from the INTL global 'default_locale'
     * @return string The current runtime locale
     */
    public static function getDefault(): string {}

    /**
     * sets the default runtime locale
     * @param string $locale Is a BCP 47 compliant language tag containing the
     * @return bool TRUE on success or FALSE on failure.
     */
    public static function setDefault($locale) {}

    /**
     * Gets the primary language for the input locale
     * @param string $locale The locale to extract the primary language code from
     * @return string|null The language code associated with the language or NULL in case of error.
     */
    public static function getPrimaryLanguage($locale): ?string {}

    /**
     * Gets the script for the input locale
     * @param string $locale The locale to extract the script code from
     * @return string|null The script subtag for the locale or NULL if not present
     */
    public static function getScript($locale): ?string {}

    /**
     * Gets the region for the input locale
     * @param string $locale The locale to extract the region code from
     * @return string|null The region subtag for the locale or NULL if not present
     */
    public static function getRegion($locale): ?string {}

    /**
     * Gets the keywords for the input locale
     * @param string $locale The locale to extract the keywords from
     * @return array|false|null Associative array containing the keyword-value pairs for this locale
     */
    public static function getKeywords($locale): array|false|null {}

    /**
     * Returns an appropriately localized display name for script of the input locale
     * @param string $locale The locale to return a display script for
     * @param string $displayLocale Optional format locale to use to display the script name
     * @return string|false Display name of the script for the $locale in the format appropriate for $in_locale.
     */
    public static function getDisplayScript(
        $locale,
        $displayLocale,
        $displayLocale = null
    ): string|false {}

    /**
     * Returns an appropriately localized display name for region of the input locale
     * @param string $locale The locale to return a display region for.
     * @param string $displayLocale Optional format locale to use to display the region name
     * @return string|false display name of the region for the $locale in the format appropriate for $in_locale.
     */
    public static function getDisplayRegion(
        $locale,
        $displayLocale,
        $displayLocale = null
    ): string|false {}

    /**
     * Returns an appropriately localized display name for the input locale
     * @param string $locale The locale to return a display name for.
     * @param string $displayLocale optional format locale
     * @return string|false Display name of the locale in the format appropriate for $in_locale.
     */
    public static function getDisplayName(
        $locale,
        $displayLocale,
        $displayLocale = null
    ): string|false {}

    /**
     * @param string $keyword
     * @param string|null $displayLocale
     * @return string|false
     * @since 8.6
     */
    public static function getDisplayKeyword(string $keyword, ?string $displayLocale = null): string|false {}

    /**
     * @param string $locale
     * @param string $keyword
     * @param string|null $displayLocale
     * @return string|false
     * @since 8.6
     */
    public static function getDisplayKeywordValue(string $locale, string $keyword, ?string $displayLocale = null): string|false {}

    /**
     * Returns an appropriately localized display name for language of the inputlocale
     * @param string $locale The locale to return a display language for
     * @param string $displayLocale Optional format locale to use to display the language name
     * @return string|false display name of the language for the $locale in the format appropriate for $in_locale.
     */
    public static function getDisplayLanguage(
        $locale,
        $displayLocale,
        $displayLocale = null
    ): string|false {}

    /**
     * Returns an appropriately localized display name for variants of the input locale
     * @param string $locale The locale to return a display variant for
     * @param string $displayLocale Optional format locale to use to display the variant name
     * @return string|false Display name of the variant for the $locale in the format appropriate for $in_locale.
     */
    public static function getDisplayVariant(
        $locale,
        $displayLocale,
        $displayLocale = null
    ): string|false {}

    /**
     * Returns a correctly ordered and delimited locale ID
     * @param array $subtags an array containing a list of key-value pairs, where the keys identify the particular locale ID subtags, and the values are the associated subtag values. The 'variant' and 'private' subtags can take maximum 15 values whereas 'extlang' can take maximum 3 values.e.g. Variants ...
     * @return string|false The corresponding locale identifier.
     */
    public static function composeLocale(array $subtags): string|false {}

    /**
     * Returns a key-value array of locale ID subtag elements.
     * @param string $locale The locale to extract the subtag array from. Note: The 'variant' and 'private' subtags can take maximum 15 values whereas 'extlang' can take maximum 3 values.
     * @return array|null an array containing a list of key-value pairs, where the keys identify the particular locale ID subtags, and the values are the associated subtag values. The array will be ordered as the locale id subtags e.g. in the locale id if variants are '-varX-varY-varZ' then the returned ...
     */
    public static function parseLocale($locale): ?array {}

    /**
     * Gets the variants for the input locale
     * @param string $locale The locale to extract the variants from
     * @return array|null The array containing the list of all variants subtag for the locale or NULL if not present
     */
    public static function getAllVariants($locale): ?array {}

    /**
     * Checks if a language tag filter matches with locale
     * @param string $languageTag The language tag to check
     * @param string $locale The language range to check against
     * @param bool $canonicalize If true, the arguments will be converted to canonical form before matching.
     * @return bool|null TRUE if $locale matches $langtag FALSE otherwise.
     */
    public static function filterMatches(
        $languageTag,
        $locale,
        $canonicalize,
        $canonicalize = false
    ): ?bool {}

    /**
     * Searches the language tag list for the best match to the language
     * @param array $languageTag An array containing a list of language tags to compare to locale. Maximum 100 items allowed.
     * @param string $locale The locale to use as the language range when matching.
     * @param bool $canonicalize If true, the arguments will be converted to canonical form before matching.
     * @param string $defaultLocale The locale to use if no match is found.
     * @return string|null The closest matching language tag or default value.
     */
    public static function lookup(
        array $languageTag,
        $locale,
        $canonicalize,
        $defaultLocale,
        $canonicalize = false,
        $defaultLocale = null
    ): ?string {}

    /**
     * Canonicalize the locale string
     *
     * Canonicalizes the passed locale string to ICU format.
     * @param string $locale Original locale string.
     * @return string|null Canonicalized locale string. Returns null when the length of locale exceeds INTL_MAX_LOCALE_LEN.
     */
    public static function canonicalize($locale): ?string {}

    /**
     * Tries to find out best available locale based on HTTP "Accept-Language" header
     * @param string $header The string containing the "Accept-Language" header according to format in RFC 2616.
     * @return string|false The corresponding locale identifier.
     */
    public static function acceptFromHttp($header): string|false {}

    /**
     * Check whether a locale uses a right-to-left writing system
     *
     * Determines whether a locale uses a right-to-left writing system.
     * @since 8.5
     */
    public static function isRightToLeft(string $locale): bool {}

    /**
     * @since 8.5
     */
    public static function addLikelySubtags(string $locale): string|false {}

    /**
     * @since 8.5
     */
    public static function minimizeSubtags(string $locale): string|false {}
}
