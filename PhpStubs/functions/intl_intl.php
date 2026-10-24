<?php

/**
 * Create a collator
 * @param string $locale The locale containing the required collation rules. Special values for locales can be passed in - if null is passed for the locale, the default locale collation rules will be used. If empty string ("") or "root" are passed, UCA rules will be used.
 * @return Collator|null Return new instance of Collator object, or NULL on error.
 */
function collator_create(string $locale): ?Collator {}

/**
 * Compare two Unicode strings
 * @param Collator $object Collator object.
 * @param string $string1 The first string to compare.
 * @param string $string2 The second string to compare.
 * @return int|false Return comparison result: 1 if string1 is greater than string2 ; 0 if string1 is equal to string2; -1 if string1 is less than string2 . On error boolean FALSE is returned.
 */
function collator_compare(Collator $object, string $string1, string $string2): int|false {}

/**
 * Get collation attribute value
 * @param Collator $object Collator object.
 * @param int $attribute Attribute to get value for.
 * @return int|false Attribute value, or boolean FALSE on error.
 */
function collator_get_attribute(Collator $object, int $attribute): int|false {}

/**
 * Set collation attribute
 * @param Collator $object Collator object.
 * @param int $attribute Attribute.
 * @param int $value Attribute value.
 * @return bool TRUE on success or FALSE on failure.
 */
function collator_set_attribute(Collator $object, int $attribute, int $value): bool {}

/**
 * Get current collation strength
 * @param Collator $object Collator object.
 * @return int current collation strength
 */
function collator_get_strength(Collator $object): int {}

/**
 * Set collation strength
 * @param Collator $object Collator object.
 * @param int $strength Strength to set. Possible values are: Collator::PRIMARY
 * @return bool TRUE on success or FALSE on failure.
 */
function collator_set_strength(Collator $object, int $strength) {}

/**
 * Sort array using specified collator
 * @param Collator $object Collator object.
 * @param string[] &$array Array of strings to sort.
 * @param int $flags Optional sorting type, one of the following: Collator::SORT_REGULAR - compare items normally (don't change types)
 * @return bool TRUE on success or FALSE on failure.
 */
function collator_sort(Collator $object, array &$array, int $flags = 0): bool {}

/**
 * Sort array using specified collator and sort keys
 * @param Collator $object Collator object.
 * @param string[] &$array Array of strings to sort
 * @return bool TRUE on success or FALSE on failure.
 */
function collator_sort_with_sort_keys(
    Collator $object,
    array &$array,
    $sort_flags = []
): bool {}

/**
 * Sort array maintaining index association
 * @param Collator $object Collator object.
 * @param string[] &$array Array of strings to sort.
 * @param int $flags Optional sorting type, one of the following: Collator::SORT_REGULAR - compare items normally (don't change types)
 * @return bool TRUE on success or FALSE on failure.
 */
function collator_asort(Collator $object, array &$array, int $flags = 0): bool {}

/**
 * Get the locale name of the collator
 * @param Collator $object Collator object.
 * @param int $type You can choose between valid and actual locale ( Locale::VALID_LOCALE and Locale::ACTUAL_LOCALE, respectively). The default is the actual locale.
 * @return string|false Real locale name from which the collation data comes. If the collator was instantiated from rules or an error occurred, returns boolean FALSE.
 */
function collator_get_locale(Collator $object, int $type): string|false {}

/**
 * Get collator's last error code
 * @param Collator $object Collator object.
 * @return int|false Error code returned by the last Collator API function call.
 */
function collator_get_error_code(Collator $object): int|false {}

/**
 * Get text for collator's last error code
 * @param Collator $object Collator object.
 * @return string|false Description of an error occurred in the last Collator API function call.
 */
function collator_get_error_message(Collator $object): string|false {}

/**
 * Get sorting key for a string
 * @param Collator $object Collator object.
 * @param string $string The string to produce the key from.
 * @return string|false the collation key for the string. Collation keys can be compared directly instead of strings.
 */
function collator_get_sort_key(
    Collator $object,
    string $string,
    $arg3
): string|false {}

/**
 * Create a number formatter
 * @param string $locale Locale in which the number would be formatted (locale name, e.g. en_CA).
 * @param int $style Style of the formatting, one of the format style constants. If NumberFormatter::PATTERN_DECIMAL or NumberFormatter::PATTERN_RULEBASED is passed then the number format is opened using the given pattern, which must conform to the syntax described in ICU DecimalFormat documentation ...
 * @param string|null $pattern [optional] Pattern string if the chosen style requires a pattern.
 * @return NumberFormatter|null NumberFormatter object or NULL on error.
 */
function numfmt_create(string $locale, int $style, $pattern = null): ?NumberFormatter {}

/**
 * Format a number
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int|float $num The value to format. Can be integer or float, other values will be converted to a numeric value.
 * @param int $type The formatting type to use.
 * @return string|false the string containing formatted value, or FALSE on error.
 */
function numfmt_format(NumberFormatter $formatter, int|float $num, int $type = 0): string|false {}

/**
 * Parse a number
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param string $string The string to parse for the number.
 * @param int $type [optional] The formatting type to use. By default, NumberFormatter::TYPE_DOUBLE is used.
 * @param int &$offset [optional] Offset in the string at which to begin parsing. On return, this value will hold the offset at which parsing ended.
 * @return int|float|false The value of the parsed number or FALSE on error.
 */
function numfmt_parse(NumberFormatter $formatter, string $string, int $type = NumberFormatter::TYPE_DOUBLE, &$offset = null): int|float|false {}

/**
 * Format a currency value
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param float $amount The numeric currency value.
 * @param string $currency The 3-letter ISO 4217 currency code indicating the currency to use.
 * @return string|false String representing the formatted currency value.
 */
function numfmt_format_currency(NumberFormatter $formatter, float $amount, string $currency): string|false {}

/**
 * Parse a currency number
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param string $string
 * @param string &$currency Parameter to receive the currency name (3-letter ISO 4217 currency code).
 * @param int &$offset [optional] Offset in the string at which to begin parsing. On return, this value will hold the offset at which parsing ended.
 * @return float|false The parsed numeric value or FALSE on error.
 */
function numfmt_parse_currency(NumberFormatter $formatter, string $string, &$currency, &$offset = null): float|false {}

/**
 * Set an attribute
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $attribute Attribute specifier - one of the numeric attribute constants.
 * @param int|float $value The attribute value.
 * @return bool TRUE on success or FALSE on failure.
 */
function numfmt_set_attribute(NumberFormatter $formatter, int $attribute, int|float $value): bool {}

/**
 * Get an attribute
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $attribute Attribute specifier - one of the numeric attribute constants.
 * @return int|float|false Return attribute value on success, or FALSE on error.
 */
function numfmt_get_attribute(NumberFormatter $formatter, int $attribute): int|float|false {}

/**
 * Set a text attribute
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $attribute Attribute specifier - one of the text attribute constants.
 * @param string $value Text for the attribute value.
 * @return bool TRUE on success or FALSE on failure.
 */
function numfmt_set_text_attribute(NumberFormatter $formatter, int $attribute, string $value): bool {}

/**
 * Get a text attribute
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $attribute Attribute specifier - one of the text attribute constants.
 * @return string|false Return attribute value on success, or FALSE on error.
 */
function numfmt_get_text_attribute(NumberFormatter $formatter, int $attribute): string|false {}

/**
 * Set a symbol value
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $symbol Symbol specifier, one of the format symbol constants.
 * @param string $value Text for the symbol.
 * @return bool TRUE on success or FALSE on failure.
 */
function numfmt_set_symbol(NumberFormatter $formatter, int $symbol, string $value): bool {}

/**
 * Get a symbol value
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $symbol Symbol specifier, one of the format symbol constants.
 * @return string|false The symbol string or FALSE on error.
 */
function numfmt_get_symbol(NumberFormatter $formatter, int $symbol): string|false {}

/**
 * Set formatter pattern
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param string $pattern Pattern in syntax described in ICU DecimalFormat documentation.
 * @return bool TRUE on success or FALSE on failure.
 */
function numfmt_set_pattern(NumberFormatter $formatter, string $pattern): bool {}

/**
 * Get formatter pattern
 * @param NumberFormatter $formatter NumberFormatter object.
 * @return string|false Pattern string that is used by the formatter, or FALSE if an error happens.
 */
function numfmt_get_pattern(NumberFormatter $formatter): string|false {}

/**
 * Get formatter locale
 * @param NumberFormatter $formatter NumberFormatter object.
 * @param int $type You can choose between valid and actual locale ( Locale::VALID_LOCALE, Locale::ACTUAL_LOCALE, respectively). The default is the actual locale.
 * @return string|false The locale name used to create the formatter.
 */
function numfmt_get_locale(NumberFormatter $formatter, int $type = 0): string|false {}

/**
 * Get formatter's last error code.
 * @param NumberFormatter $formatter NumberFormatter object.
 * @return int error code from last formatter call.
 */
function numfmt_get_error_code(NumberFormatter $formatter): int {}

/**
 * Get formatter's last error message.
 * @param NumberFormatter $formatter NumberFormatter object.
 * @return string error message from last formatter call.
 */
function numfmt_get_error_message(NumberFormatter $formatter): string {}

/**
 * Normalizes the input provided and returns the normalized string
 * @param string $string The input string to normalize
 * @param int $form [optional] One of the normalization forms.
 * @return string|false The normalized string or FALSE if an error occurred.
 */
function normalizer_normalize(string $string, int $form = Normalizer::FORM_C): string|false {}

/**
 * Checks if the provided string is already in the specified normalization
 * form.
 * @param string $string The input string to normalize
 * @param int $form [optional] One of the normalization forms.
 * @return bool TRUE if normalized, FALSE otherwise or if there an error
 */
function normalizer_is_normalized(string $string, int $form = Normalizer::FORM_C): bool {}

/**
 * Gets the default locale value from the intl global 'default_locale'
 * @return string a string with the current Locale.
 */
function locale_get_default(): string {}

/**
 * Set the default runtime Locale
 * @param string $locale The new Locale name. A comprehensive list of the supported locales is available at .
 * @return bool TRUE on success or FALSE on failure.
 */
function locale_set_default(string $locale) {}

/**
 * Gets the primary language for the input locale
 * @param string $locale The locale to extract the primary language code from
 * @return string|null The language code associated with the language or NULL in case of error.
 */
function locale_get_primary_language(string $locale): ?string {}

/**
 * Gets the script for the input locale
 * @param string $locale The locale to extract the script code from
 * @return string|null The script subtag for the locale or NULL if not present
 */
function locale_get_script(string $locale): ?string {}

/**
 * Gets the region for the input locale
 * @param string $locale The locale to extract the region code from
 * @return string|null The region subtag for the locale or NULL if not present
 */
function locale_get_region(string $locale): ?string {}

/**
 * Gets the keywords for the input locale
 * @param string $locale The locale to extract the keywords from
 * @return array|false|null Associative array containing the keyword-value pairs for this locale
 */
function locale_get_keywords(string $locale): array|false|null {}

/**
 * Returns an appropriately localized display name for script of the input locale
 * @param string $locale The locale to return a display script for
 * @param string|null $displayLocale Optional format locale to use to display the script name
 * @return string|false Display name of the script for the $locale in the format appropriate for $in_locale.
 */
function locale_get_display_script(
    string $locale,
    ?string $displayLocale,
    ?string $displayLocale = null
): string|false {}

/**
 * Returns an appropriately localized display name for region of the input locale
 * @param string $locale The locale to return a display region for.
 * @param string|null $displayLocale Optional format locale to use to display the region name
 * @return string|false display name of the region for the $locale in the format appropriate for $in_locale.
 */
function locale_get_display_region(
    string $locale,
    ?string $displayLocale,
    ?string $displayLocale = null
): string|false {}

/**
 * Returns an appropriately localized display name for the input locale
 * @param string $locale The locale to return a display name for.
 * @param string|null $displayLocale optional format locale
 * @return string|false Display name of the locale in the format appropriate for $in_locale.
 */
function locale_get_display_name(
    string $locale,
    ?string $displayLocale,
    ?string $displayLocale = null
): string|false {}

/**
 * Returns an appropriately localized display name for language of the inputlocale
 * @param string $locale The locale to return a display language for
 * @param string|null $displayLocale Optional format locale to use to display the language name
 * @return string|false display name of the language for the $locale in the format appropriate for $in_locale.
 */
function locale_get_display_language(
    string $locale,
    ?string $displayLocale,
    ?string $displayLocale = null
): string|false {}

/**
 * Returns an appropriately localized display name for variants of the input locale
 * @param string $locale The locale to return a display variant for
 * @param string|null $displayLocale Optional format locale to use to display the variant name
 * @return string|false Display name of the variant for the $locale in the format appropriate for $in_locale.
 */
function locale_get_display_variant(
    string $locale,
    ?string $displayLocale,
    ?string $displayLocale = null
): string|false {}

/**
 * Returns an appropriately localized display name for the given keyword
 * @param string $keyword The keyword to return a display name for.
 * @param string|null $displayLocale Optional format locale to use to display the keyword name
 * @return string|false Display name of the keyword in the format appropriate for $displayLocale, or FALSE on failure.
 * @since 8.6
 */
function locale_get_display_keyword(string $keyword, ?string $displayLocale = null): string|false {}

/**
 * Returns an appropriately localized display name for the value of the given keyword
 * @param string $locale The locale that contains the keyword value.
 * @param string $keyword The keyword whose value should be returned.
 * @param string|null $displayLocale Optional format locale to use to display the keyword value
 * @return string|false Display name of the keyword value in the format appropriate for $displayLocale, or FALSE on failure.
 * @since 8.6
 */
function locale_get_display_keyword_value(string $locale, string $keyword, ?string $displayLocale = null): string|false {}

/**
 * Returns a correctly ordered and delimited locale ID
 * @param string[] $subtags an array containing a list of key-value pairs, where the keys identify the particular locale ID subtags, and the values are the associated subtag values. The 'variant' and 'private' subtags can take maximum 15 values whereas 'extlang' can take maximum 3 values.e.g. Variants ...
 * @return string|false The corresponding locale identifier.
 */
function locale_compose(array $subtags): string|false {}

/**
 * Returns a key-value array of locale ID subtag elements.
 * @param string $locale The locale to extract the subtag array from. Note: The 'variant' and 'private' subtags can take maximum 15 values whereas 'extlang' can take maximum 3 values.
 * @return string[]|null an array containing a list of key-value pairs, where the keys identify the particular locale ID subtags, and the values are the associated subtag values. The array will be ordered as the locale id subtags e.g. in the locale id if variants are '-varX-varY-varZ' then the ...
 */
function locale_parse(string $locale): ?array {}

/**
 * Gets the variants for the input locale
 * @param string $locale The locale to extract the variants from
 * @return array|null The array containing the list of all variants subtag for the locale or NULL if not present
 */
function locale_get_all_variants(string $locale): ?array {}

/**
 * Checks if a language tag filter matches with locale
 * @param string $languageTag The language tag to check
 * @param string $locale The language range to check against
 * @param bool $canonicalize If true, the arguments will be converted to canonical form before matching.
 * @return bool|null TRUE if $locale matches $langtag FALSE otherwise.
 */
function locale_filter_matches(
    string $languageTag,
    string $locale,
    bool $canonicalize,
    bool $canonicalize = false
): ?bool {}

/**
 * Canonicalize the locale string
 * @param string $locale
 * @return null|string
 */
function locale_canonicalize(string $locale): ?string {}

/**
 * Searches the language tag list for the best match to the language
 * @param string[] $languageTag An array containing a list of language tags to compare to locale. Maximum 100 items allowed.
 * @param string $locale The locale to use as the language range when matching.
 * @param bool $canonicalize If true, the arguments will be converted to canonical form before matching.
 * @param string|null $defaultLocale The locale to use if no match is found.
 * @return string|null The closest matching language tag or default value.
 */
function locale_lookup(
    array $languageTag,
    string $locale,
    bool $canonicalize,
    ?string $defaultLocale,
    bool $canonicalize = false,
    ?string $defaultLocale = null,
): ?string {}

/**
 * Tries to find out best available locale based on HTTP "Accept-Language" header
 * @param string $header The string containing the "Accept-Language" header according to format in RFC 2616.
 * @return string|false The corresponding locale identifier.
 */
function locale_accept_from_http(string $header): string|false {}

/**
 * Constructs a new message formatter
 * @param string $locale The locale to use when formatting arguments
 * @param string $pattern The pattern string to stick arguments into. The pattern uses an 'apostrophe-friendly' syntax; see Quoting/Escaping for details.
 * @return MessageFormatter|null The formatter object, or null on failure.
 */
function msgfmt_create(string $locale, string $pattern): ?MessageFormatter {}

/**
 * Format the message
 * @param MessageFormatter $formatter The message formatter
 * @param array $values Arguments to insert into the format string
 * @return string|false The formatted string, or FALSE if an error occurred
 */
function msgfmt_format(MessageFormatter $formatter, array $values): string|false {}

/**
 * Quick format message
 * @param string $locale The locale to use for formatting locale-dependent parts
 * @param string $pattern The pattern string to insert things into. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
 * @param array $values The array of values to insert into the format string
 * @return string|false The formatted pattern string or FALSE if an error occurred
 */
function msgfmt_format_message(string $locale, string $pattern, array $values): string|false {}

/**
 * Parse input string according to pattern
 * @param MessageFormatter $formatter The message formatter
 * @param string $string The string to parse
 * @return array|false An array containing the items extracted, or FALSE on error
 */
function msgfmt_parse(MessageFormatter $formatter, string $string): array|false {}

/**
 * Quick parse input string
 * @param string $locale The locale to use for parsing locale-dependent parts
 * @param string $pattern The pattern with which to parse the value.
 * @param string $message The string to parse, conforming to the pattern.
 * @return array|false An array containing items extracted, or FALSE on error
 */
function msgfmt_parse_message(string $locale, string $pattern, string $message): array|false {}

/**
 * Set the pattern used by the formatter
 * @param MessageFormatter $formatter The message formatter
 * @param string $pattern The pattern string to use in this message formatter. The pattern uses an 'apostrophe-friendly' syntax; it is run through umsg_autoQuoteApostrophe before being interpreted.
 * @return bool TRUE on success or FALSE on failure.
 */
function msgfmt_set_pattern(MessageFormatter $formatter, string $pattern): bool {}

/**
 * Get the pattern used by the formatter
 * @param MessageFormatter $formatter The message formatter
 * @return string|false The pattern string for this message formatter
 */
function msgfmt_get_pattern(MessageFormatter $formatter): string|false {}

/**
 * Get the locale for which the formatter was created.
 * @param MessageFormatter $formatter The formatter resource
 * @return string The locale name
 */
function msgfmt_get_locale(MessageFormatter $formatter): string {}

/**
 * Get the error code from last operation
 * @param MessageFormatter $formatter The message formatter
 * @return int The error code, one of UErrorCode values. Initial value is U_ZERO_ERROR.
 */
function msgfmt_get_error_code(MessageFormatter $formatter): int {}

/**
 * Get the error text from the last operation
 * @param MessageFormatter $formatter The message formatter
 * @return string Description of the last error.
 */
function msgfmt_get_error_message(MessageFormatter $formatter): string {}

/**
 * Create a date formatter
 * @param string|null $locale Locale to use when formatting or parsing.
 * @param int $dateType Date type to use (none, short, medium, long, full). This is one of the IntlDateFormatter constants.
 * @param int $timeType Time type to use (none, short, medium, long, full). This is one of the IntlDateFormatter constants.
 * @param string|null $timezone [optional] Time zone ID, default is system default.
 * @param IntlCalendar|int|null $calendar [optional] Calendar to use for formatting or parsing; default is Gregorian. This is one of the IntlDateFormatter calendar constants.
 * @param string|null $pattern [optional] Optional pattern to use when formatting or parsing. Possible patterns are documented at http://userguide.icu-project.org/formatparse/datetime.
 * @return IntlDateFormatter|null The created IntlDateFormatter or null in case of failure.
 */
function datefmt_create(
    ?string $locale,
    int $dateType,
    int $dateType = 0,
    int $timeType,
    int $timeType = 0,
    $timezone = null,
    IntlCalendar|int|null $calendar = null,
    $pattern = null
): ?IntlDateFormatter {}

/**
 * Get the datetype used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return int|false The current date type value of the formatter.
 */
function datefmt_get_datetype(IntlDateFormatter $formatter): int|false {}

/**
 * Get the timetype used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return int|false The current date type value of the formatter.
 */
function datefmt_get_timetype(IntlDateFormatter $formatter): int|false {}

/**
 * Get the calendar type used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource
 * @return int|false The calendar being used by the formatter.
 */
function datefmt_get_calendar(IntlDateFormatter $formatter): int|false {}

/**
 * sets the calendar used to the appropriate calendar, which must be
 * @param IntlDateFormatter $formatter $mf
 * @param IntlCalendar|int|null $calendar The calendar to use. Default is IntlDateFormatter::GREGORIAN.
 * @return bool TRUE on success or FALSE on failure.
 */
function datefmt_set_calendar(IntlDateFormatter $formatter, IntlCalendar|int|null $calendar): bool {}

/**
 * Get the locale used by formatter
 * @param IntlDateFormatter $formatter The formatter resource
 * @param int $type [optional]
 * @return string|false the locale of this formatter or 'false' if error
 */
function datefmt_get_locale(
    IntlDateFormatter $formatter,
    int $type = ULOC_ACTUAL_LOCALE
): string|false {}

/**
 * Get the timezone-id used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return string|false ID string for the time zone used by this formatter.
 */
function datefmt_get_timezone_id(IntlDateFormatter $formatter): string|false {}

/**
 * Get copy of formatter's calendar object
 * @param IntlDateFormatter $formatter
 * @return IntlCalendar|false|null A copy of the internal calendar object used by this formatter.
 */
function datefmt_get_calendar_object(IntlDateFormatter $formatter): IntlCalendar|false|null {}

/**
 * Get formatter's timezone
 * @param IntlDateFormatter $formatter
 * @return IntlTimeZone|false The associated IntlTimeZone object or FALSE on failure.
 */
function datefmt_get_timezone(IntlDateFormatter $formatter): IntlTimeZone|false {}

/**
 * Sets the time zone to use
 * @param MessageFormatter $mf
 * @param string $zone The time zone ID string of the time zone to use. If NULL or the empty string, the default time zone for the runtime is used.
 * @return bool TRUE on success or FALSE on failure.
 * @removed 7.0
 * @see datefmt_set_timezone()
 * @deprecated
 */
function datefmt_set_timezone_id(MessageFormatter $mf, $zone) {}

/**
 * Sets formatter's timezone
 * @param IntlDateFormatter $formatter The formatter resource.
 * @param IntlTimeZone|DateTimeZone|string|null $timezone The timezone to use for this formatter. This can be specified in the following forms: NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() and ...
 * @return bool|null TRUE on success or FALSE on failure.
 */
function datefmt_set_timezone(IntlDateFormatter $formatter, $timezone) {}

/**
 * Get the pattern used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return string|false The pattern string being used to format/parse.
 */
function datefmt_get_pattern(IntlDateFormatter $formatter): string|false {}

/**
 * Set the pattern used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @param string $pattern New pattern string to use. Possible patterns are documented at http://userguide.icu-project.org/formatparse/datetime.
 * @return bool TRUE on success or FALSE on failure. Bad formatstrings are usually the cause of the failure.
 */
function datefmt_set_pattern(IntlDateFormatter $formatter, string $pattern): bool {}

/**
 * Get the lenient used for the IntlDateFormatter
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return bool TRUE if parser is lenient, FALSE if parser is strict. By default the parser is lenient.
 */
function datefmt_is_lenient(IntlDateFormatter $formatter): bool {}

/**
 * Set the leniency of the parser
 * @param IntlDateFormatter $formatter The formatter resource
 * @param bool $lenient Sets whether the parser is lenient or not, default is TRUE (lenient).
 * @return void Returns true on success or false on failure.
 */
function datefmt_set_lenient(
    IntlDateFormatter $formatter,
    bool $lenient
): void {}

/**
 * Format the date/time value as a string
 * @param IntlDateFormatter $formatter The date formatter resource.
 * @param object|array|string|int|float $datetime Value to format. This may be a DateTime object, an integer representing a Unix timestamp value (seconds since epoch, UTC) or an array in the format output by localtime.
 * @return string|false The formatted string or, if an error occurred, FALSE.
 */
function datefmt_format(
    $formatter = null,
    $formatter,
    $datetime = null,
    $datetime
): string|false {}

/**
 * Formats an object
 * @param IntlCalendar|DateTimeInterface $datetime An object of type IntlCalendar or DateTime. The timezone information in the object will be used.
 * @param array|int|string|null $format [optional] How to format the date/time. This can either be an {https://secure.php.net/manual/en/language.types.array.php array}  with two elements (first the date style, then the time style, these being one of the constants IntlDateFormatter::NONE, ...
 * @param string|null $locale [optional] The locale to use, or NULL to use the default one.
 * @return string|false The formatted string or, if an error occurred, FALSE.
 */
function datefmt_format_object($datetime, $format = null, ?string $locale = null): string|false {}

/**
 * Parse string to a timestamp value
 * @param IntlDateFormatter $formatter The formatter resource
 * @param string $string string to convert to a time
 * @param int &$offset [optional] Position at which to start the parsing in $value (zero-based). If no error occurs before $value is consumed, $parse_pos will contain -1 otherwise it will contain the position at which parsing ended (and the error occurred). This variable will contain the end position ...
 * @return int|float|false timestamp parsed value
 */
function datefmt_parse(IntlDateFormatter $formatter, string $string, &$offset = null): int|float|false {}

/**
 * Parse string to a field-based time value
 * @param IntlDateFormatter $formatter The formatter resource
 * @param string $string string to convert to a time
 * @param int &$offset [optional] Position at which to start the parsing in $value (zero-based). If no error occurs before $value is consumed, $parse_pos will contain -1 otherwise it will contain the position at which parsing ended . If $parse_pos > strlen($value), the parse fails immediately.
 * @return array|false Localtime compatible array of integers : contains 24 hour clock value in tm_hour field
 */
function datefmt_localtime(IntlDateFormatter $formatter, string $string, &$offset = null): array|false {}

/**
 * Get the error code from last operation
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return int The error code, one of UErrorCode values. Initial value is U_ZERO_ERROR.
 */
function datefmt_get_error_code(IntlDateFormatter $formatter): int {}

/**
 * Get the error text from the last operation.
 * @param IntlDateFormatter $formatter The formatter resource.
 * @return string Description of the last error.
 */
function datefmt_get_error_message(IntlDateFormatter $formatter): string {}

/**
 * Get string length in grapheme units
 * @param string $string The string being measured for length. It must be a valid UTF-8 string.
 * @return int|false|null The length of the string on success, and 0 if the string is empty.
 */
function grapheme_strlen(string $string): int|false|null {}

/**
 * Find position (in grapheme units) of first occurrence of a string
 * @param string $haystack The string to look in. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param int $offset [optional] The optional $offset parameter allows you to specify where in $haystack to start searching as an offset in grapheme units (not bytes or characters). The position returned is still relative to the beginning of haystack regardless of the value of $offset.
 * @param string $locale Locale to use.
 * @return int|false the position as an integer. If needle is not found, strpos() will return boolean FALSE.
 */
function grapheme_strpos(string $haystack, string $needle, int $offset = 0, string $locale = ""): int|false {}

/**
 * Find position (in grapheme units) of first occurrence of a case-insensitive string
 * @param string $haystack The string to look in. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param int $offset [optional] The optional $offset parameter allows you to specify where in haystack to start searching as an offset in grapheme units (not bytes or characters). The position returned is still relative to the beginning of haystack regardless of the value of $offset.
 * @param string $locale Locale to use.
 * @return int|false the position as an integer. If needle is not found, grapheme_stripos() will return boolean FALSE.
 */
function grapheme_stripos(string $haystack, string $needle, int $offset = 0, string $locale = ""): int|false {}

/**
 * Find position (in grapheme units) of last occurrence of a string
 * @param string $haystack The string to look in. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param int $offset [optional] The optional $offset parameter allows you to specify where in $haystack to start searching as an offset in grapheme units (not bytes or characters). The position returned is still relative to the beginning of haystack regardless of the value of $offset.
 * @param string $locale Locale to use.
 * @return int|false the position as an integer. If needle is not found, grapheme_strrpos() will return boolean FALSE.
 */
function grapheme_strrpos(string $haystack, string $needle, int $offset = 0, string $locale = ""): int|false {}

/**
 * Find position (in grapheme units) of last occurrence of a case-insensitive string
 * @param string $haystack The string to look in. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param int $offset [optional] The optional $offset parameter allows you to specify where in $haystack to start searching as an offset in grapheme units (not bytes or characters). The position returned is still relative to the beginning of haystack regardless of the value of $offset.
 * @param string $locale Locale to use.
 * @return int|false the position as an integer. If needle is not found, grapheme_strripos() will return boolean FALSE.
 */
function grapheme_strripos(string $haystack, string $needle, int $offset = 0, string $locale = ""): int|false {}

/**
 * Return part of a string
 * @param string $string The input string. Must be valid UTF-8.
 * @param int $offset Start position in default grapheme units. If $start is non-negative, the returned string will start at the $start'th position in $string, counting from zero. If $start is negative, the returned string will start at the $start'th grapheme unit from the end of string.
 * @param int|null $length [optional] Length in grapheme units. If $length is given and is positive, the string returned will contain at most $length grapheme units beginning from $start (depending on the length of string). If $length is given and is negative, then that many grapheme units will be ...
 * @param string $locale Locale to use.
 * @return string|false the extracted part of $string, or FALSE if $length is negative and $start denotes a position beyond truncation $length, or also FALSE if $start denotes a position beyond $string length
 */
function grapheme_substr(string $string, int $offset, ?int $length = null, string $locale = ""): string|false {}

/**
 * Reverses a string on a grapheme cluster level.
 * @param string $string The input string. Must be valid UTF-8.
 * @return string|false The reversed string, or FALSE on failure.
 * @since 8.6
 */
function grapheme_strrev(string $string): string|false {}

/**
 * Returns part of haystack string from the first occurrence of needle to the end of haystack.
 * @param string $haystack The input string. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param bool $beforeNeedle [optional] If TRUE, grapheme_strstr() returns the part of the haystack before the first occurrence of the needle (excluding the needle).
 * @param string $locale Locale to use.
 * @return string|false the portion of string, or FALSE if needle is not found.
 */
function grapheme_strstr(string $haystack, string $needle, bool $beforeNeedle = false, string $locale = ""): string|false {}

/**
 * Returns part of haystack string from the first occurrence of case-insensitive needle to the end of haystack.
 * @param string $haystack The input string. Must be valid UTF-8.
 * @param string $needle The string to look for. Must be valid UTF-8.
 * @param bool $beforeNeedle [optional] If TRUE, grapheme_strstr() returns the part of the haystack before the first occurrence of the needle (excluding needle).
 * @param string $locale Locale to use.
 * @return string|false the portion of $haystack, or FALSE if $needle is not found.
 */
function grapheme_stristr(string $haystack, string $needle, bool $beforeNeedle = false, string $locale = ""): string|false {}

/**
 * Function to extract a sequence of default grapheme clusters from a text buffer, which must be encoded in UTF-8.
 * @param string $haystack String to search.
 * @param int $size Maximum number items - based on the $extract_type - to return.
 * @param int $type Defines the type of units referred to by the $size parameter: GRAPHEME_EXTR_COUNT (default) - $size is the number of default grapheme clusters to extract. GRAPHEME_EXTR_MAXBYTES - $size is the maximum number of bytes returned. GRAPHEME_EXTR_MAXCHARS - $size is the maximum number of ...
 * @param int $offset [optional] Starting position in $haystack in bytes - if given, it must be zero or a positive value that is less than or equal to the length of $haystack in bytes. If $start does not point to the first byte of a UTF-8 character, the start position is moved to the next character ...
 * @param int &$next [optional] Reference to a value that will be set to the next starting position. When the call returns, this may point to the first byte position past the end of the string.
 * @return string|false A string starting at offset $start and ending on a default grapheme cluster boundary that conforms to the $size and $extract_type specified.
 */
function grapheme_extract(string $haystack, int $size, int $type = 0, int $offset = 0, &$next = null): string|false {}

/**
 * Convert domain name to IDNA ASCII form.
 * @param string $domain Domain to convert. In PHP 5 must be UTF-8 encoded. If e.g. an ISO-8859-1 (aka Western Europe latin1) encoded string is passed it will be converted into an ACE encoded "xn--" string. It will not be the one you expected though!
 * @param int $flags [optional] Conversion options - combination of IDNA_* constants (except IDNA_ERROR_* constants).
 * @param int $variant [optional] Either INTL_IDNA_VARIANT_2003 for IDNA 2003 or INTL_IDNA_VARIANT_UTS46 for UTS #46.
 * @param array &$idna_info [optional] This parameter can be used only if INTL_IDNA_VARIANT_UTS46 was used for variant. In that case, it will be filled with an array with the keys 'result', the possibly illegal result of the transformation, 'isTransitionalDifferent', a boolean indicating whether the ...
 * @return string|false The ACE encoded version of the domain name or FALSE on failure.
 */
function idn_to_ascii(string $domain, int $flags = IDNA_DEFAULT, int $variant = INTL_IDNA_VARIANT_UTS46, &$idna_info = null): string|false {}

/**
 * Convert domain name from IDNA ASCII to Unicode.
 * @param string $domain Domain to convert in IDNA ASCII-compatible format. The ASCII encoded domain name. Looks like "xn--..." if the it originally contained non-ASCII characters.
 * @param int $flags [optional] Conversion options - combination of IDNA_* constants (except IDNA_ERROR_* constants).
 * @param int $variant [optional] Either INTL_IDNA_VARIANT_2003 for IDNA 2003 or INTL_IDNA_VARIANT_UTS46 for UTS #46.
 * @param array &$idna_info [optional] This parameter can be used only if INTL_IDNA_VARIANT_UTS46 was used for variant. In that case, it will be filled with an array with the keys 'result', the possibly illegal result of the transformation, 'isTransitionalDifferent', a boolean indicating whether the ...
 * @return string|false The UTF-8 encoded version of the domain name or FALSE on failure. RFC 3490 4.2 states though "ToUnicode never fails. If any step fails, then the original input sequence is returned immediately in that step."
 */
function idn_to_utf8(string $domain, int $flags = IDNA_DEFAULT, int $variant = INTL_IDNA_VARIANT_UTS46, &$idna_info = null): string|false {}

/**
 * Create a new IntlCalendar
 * @param IntlTimeZone|DateTimeZone|string|null $timezone [optional] The timezone to use. NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() and as returned by date_default_timezone_get(). An ...
 * @param string|null $locale [optional] A locale to use or NULL to use the default locale.
 * @return IntlCalendar|null The created IntlCalendar instance or NULL on failure.
 * @since 5.5
 */
function intlcal_create_instance($timezone = null, ?string $locale = null): ?IntlCalendar {}

/**
 * Get set of locale keyword values
 * @param string $keyword The locale keyword for which relevant values are to be queried. Only 'calendar' is supported.
 * @param string $locale The locale onto which the keyword/value pair are to be appended.
 * @param bool $onlyCommon Whether to show only the values commonly used for the specified locale.
 * @return IntlIterator|false An iterator that yields strings with the locale keyword values or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_keyword_values_for_locale(string $keyword, string $locale, bool $onlyCommon): IntlIterator|false {}

/**
 * Get number representing the current time
 * @return float A float representing a number of milliseconds since the epoch, not counting leap seconds.
 * @since 5.5
 */
function intlcal_get_now(): float {}

/**
 * Get array of locales for which there is data
 * @return string[] An array of strings, one for which locale.
 * @since 5.5
 */
function intlcal_get_available_locales(): array {}

/**
 * Get the value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An integer with the value of the time field.
 * @since 5.5
 */
function intl_get($calendar, $field) {}

/**
 * Get time currently represented by the object
 * @param IntlCalendar $calendar The calendar whose time will be checked against this object's time.
 * @return float A float representing the number of milliseconds elapsed since the reference time (1 Jan 1970 00:00:00 UTC).
 * @since 5.5
 */
function intlcal_get_time(IntlCalendar $calendar) {}

/**
 * Set the calendar time in milliseconds since the epoch
 * @param IntlCalendar $calendar The IntlCalendar resource.
 * @param float $timestamp An instant represented by the number of number of milliseconds between such instant and the epoch, ignoring leap seconds.
 * @return bool Returns TRUE on success and FALSE on failure.
 * @since 5.5
 */
function intlcal_set_time(IntlCalendar $calendar, float $timestamp): bool {}

/**
 * Add a (signed) amount of time to a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @param int $value The signed amount to add to the current field. If the amount is positive, the instant will be moved forward; if it is negative, the instant wil be moved into the past. The unit is implicit to the field type. For instance, hours for IntlCalendar::FIELD_HOUR_OF_DAY.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function intlcal_add(IntlCalendar $calendar, int $field, int $value): bool {}

/**
 * Set the timezone used by this calendar
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param IntlTimeZone|DateTimeZone|string|null $timezone The new timezone to be used by this calendar. It can be specified in the following ways: NULL, in which case the default timezone will be used, as specified in the ini setting date.timezone or through the function  date_default_timezone_set() ...
 * @return bool Returns TRUE on success and FALSE on failure.
 * @since 5.5
 */
function intlcal_set_time_zone(IntlCalendar $calendar, $timezone): bool {}

/**
 * Whether this object's time is after that of the passed object
 * https://secure.php.net/manual/en/intlcalendar.after.php
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param IntlCalendar $other The calendar whose time will be checked against this object's time.
 * @return bool Returns TRUE if this object's current time is after that of the calendar argument's time. Returns FALSE otherwise. Also returns FALSE on failure. You can use exceptions or intl_get_error_code() to detect error conditions.
 * @since 5.5
 */
function intlcal_after(IntlCalendar $calendar, IntlCalendar $other): bool {}

/**
 * Whether this object's time is before that of the passed object
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param IntlCalendar $other  The calendar whose time will be checked against this object's time.
 * @return bool Returns TRUE</B> if this object's current time is before that of the calendar argument's time. Returns FALSE otherwise. Also returns FALSE on failure. You can use exceptions or intl_get_error_code() to detect error conditions.
 * @since 5.5
 */
function intlcal_before(IntlCalendar $calendar, IntlCalendar $other): bool {}

/**
 * Set a time field or several common fields at once
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $year One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @param int $month The new value for IntlCalendar::FIELD_MONTH.
 * @param int $dayOfMonth [optional] The new value for IntlCalendar::FIELD_DAY_OF_MONTH. The month sequence is zero-based, i.e., January is represented by 0, February by 1, ..., December is 11 and Undecember (if the calendar has it) is 12.
 * @param int $hour [optional] The new value for IntlCalendar::FIELD_HOUR_OF_DAY.
 * @param int $minute [optional] The new value for IntlCalendar::FIELD_MINUTE.
 * @param int $second [optional] The new value for IntlCalendar::FIELD_SECOND.
 * @return bool Returns TRUE on success and FALSE on failure.
 * @since 5.5
 */
function intlcal_set(IntlCalendar $calendar, int $year, int $month, int $dayOfMonth, int $hour, int $minute, int $second) {}

/**
 * Add value to field without carrying into more significant fields
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @param int|bool $value The (signed) amount to add to the field, TRUE for rolling up (adding 1), or FALSE for rolling down (subtracting 1).
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function intlcal_roll(
    IntlCalendar $calendar,
    int $field,
    $value = null,
    $value
): bool {}

/**
 * Clear a field or all fields
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int|null $field [optional] One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return bool Returns TRUE on success or FALSE on failure. Failure can only occur is invalid arguments are provided.
 * @since 5.5
 */
function intlcal_clear(IntlCalendar $calendar, ?int $field = null) {}

/**
 * Calculate difference between given time and this object's time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param float $timestamp The time against which to compare the quantity represented by the field. For the result to be positive, the time given for this parameter must be ahead of the time of the object the method is being invoked on.
 * @param int $field The field that represents the quantity being compared. One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int Returns a (signed) difference of time in the unit associated with the specified field or FALSE on failure.
 * @since 5.5
 */
function intlcal_field_difference(IntlCalendar $calendar, float $timestamp, int $field) {}

/**
 * The maximum value for a field, considering the object's current time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing the maximum value in the units associated with the given field or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_actual_maximum(IntlCalendar $calendar, int $field) {}

/**
 * The minimum value for a field, considering the object's current time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing the minimum value in the field's unit or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_actual_minimum(IntlCalendar $calendar, int $field) {}

/**
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
 * @return int Returns one of the constants IntlCalendar::DOW_TYPE_WEEKDAY, IntlCalendar::DOW_TYPE_WEEKEND, IntlCalendar::DOW_TYPE_WEEKEND_OFFSET or IntlCalendar::DOW_TYPE_WEEKEND_CEASE or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_day_of_week_type(IntlCalendar $calendar, int $dayOfWeek) {}

/**
 * Get the first day of the week for the calendar's locale
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return int One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_first_day_of_week(IntlCalendar $calendar) {}

/**
 * Get the largest local minimum value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing a field value, in the field's unit, or FALSE on failure.
 * @since 5.5
 */
function intlcal_greates_minimum($calendar, $field) {}

/**
 * Gets the value for a specific field.
 * @param IntlCalendar $calendar The IntlCalendar resource.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An integer with the value of the time field.
 */
function intlcal_get(IntlCalendar $calendar, int $field) {}

/**
 * Get the smallest local maximum for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing a field value in the field's unit or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_least_maximum(IntlCalendar $calendar, int $field) {}

/**
 * Get the largest local minimum value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing a field value, in the field's unit, or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_greatest_minimum(IntlCalendar $calendar, int $field) {}

/**
 * Get the locale associated with the object
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $type Whether to fetch the actual locale (the locale from which the calendar data originates, with Locale::ACTUAL_LOCALE) or the valid locale, i.e., the most specific locale supported by ICU relatively to the requested locale – see Locale::VALID_LOCALE. From the most general to the most ...
 * @return string A locale string or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_locale(IntlCalendar $calendar, int $type) {}

/**
 * Get the global maximum value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int|false
 * @since 5.5
 */
function intcal_get_maximum($calendar, $field) {}

/**
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return int An int representing a number of days or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_minimal_days_in_first_week(IntlCalendar $calendar) {}

/**
 * Get the global minimum value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int An int representing a value for the given field in the field's unit or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_minimum(IntlCalendar $calendar, int $field) {}

/**
 * Get the object's timezone
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return IntlTimeZone|false An IntlTimeZone object corresponding to the one used internally in this object.
 * @since 5.5
 */
function intlcal_get_time_zone(IntlCalendar $calendar): IntlTimeZone|false {}

/**
 * Get the calendar type
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return string A string representing the calendar type, such as 'gregorian', 'islamic', etc.
 * @since 5.5
 */
function intlcal_get_type(IntlCalendar $calendar): string {}

/**
 * Get time of the day at which weekend begins or ends
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
 * @return int The number of milliseconds into the day at which the the weekend begins or ends or FALSE on failure.
 * @since 5.5
 */
function intlcal_get_weekend_transition(IntlCalendar $calendar, int $dayOfWeek) {}

/**
 * Whether the object's time is in Daylight Savings Time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return bool Returns TRUE if the date is in Daylight Savings Time, FALSE otherwise. The value FALSE may also be returned on failure, for instance after specifying invalid field values on non-lenient mode; use exceptions or query intl_get_error_code() to disambiguate.
 * @since 5.5
 */
function intlcal_in_daylight_time(IntlCalendar $calendar): bool {}

/**
 * Whether date/time interpretation is in lenient mode
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return bool A bool representing whether the calendar is set to lenient mode.
 * @since 5.5
 */
function intlcal_is_lenient(IntlCalendar $calendar): bool {}

/**
 * Whether a field is set
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return bool Assuming there are no argument errors, returns TRUE iif the field is set.
 * @since 5.5
 */
function intlcal_is_set(IntlCalendar $calendar, int $field): bool {}

/**
 * Get the global maximum value for a field
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $field One of the IntlCalendar date/time field constants. These are integer values between 0 and IntlCalendar::FIELD_COUNT.
 * @return int|false
 * @since 5.5
 */
function intlcal_get_maximum(IntlCalendar $calendar, int $field) {}

/**
 * Whether another calendar is equal but for a different time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param IntlCalendar $other The other calendar against which the comparison is to be made.
 * @return bool Assuming there are no argument errors, returns TRUE iif the calendars are equivalent except possibly for their set time.
 * @since 5.5
 */
function intlcal_is_equivalent_to(IntlCalendar $calendar, IntlCalendar $other): bool {}

/**
 * Whether a certain date/time is in the weekend
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param float|null $timestamp [optional] An optional timestamp representing the number of milliseconds since the epoch, excluding leap seconds. If NULL, this object's current time is used instead.
 * @return bool A bool indicating whether the given or this object's time occurs in a weekend. The value FALSE may also be returned on failure, for instance after giving a date out of bounds on non-lenient mode; use exceptions or query intl_get_error_code() to disambiguate.
 * @since 5.5
 */
function intlcal_is_weekend(IntlCalendar $calendar, ?float $timestamp = null): bool {}

/**
 * Set the day on which the week is deemed to start
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $dayOfWeek One of the constants IntlCalendar::DOW_SUNDAY, IntlCalendar::DOW_MONDAY, ..., IntlCalendar::DOW_SATURDAY.
 * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
 * @since 5.5
 */
function intlcal_set_first_day_of_week(IntlCalendar $calendar, int $dayOfWeek) {}

/**
 * Set whether date/time interpretation is to be lenient
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param bool $lenient Use TRUE to activate the lenient mode; FALSE otherwise.
 * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
 * @since 5.5
 */
function intlcal_set_lenient(IntlCalendar $calendar, bool $lenient) {}

/**
 * Get behavior for handling repeating wall time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return int One of the constants IntlCalendar::WALLTIME_FIRST or IntlCalendar::WALLTIME_LAST.
 * @since 5.5
 */
function intlcal_get_repeated_wall_time_option(IntlCalendar $calendar): int {}

/**
 * Compare time of two IntlCalendar objects for equality
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param IntlCalendar $other
 * @return bool Returns TRUE if the current time of both this and the passed in IntlCalendar object are the same, or FALSE otherwise. The value FALSE can also be returned on failure. This can only happen if bad arguments are passed in. In any case, the two cases can be distinguished by calling  ...
 * @since 5.5
 */
function intlcal_equals(IntlCalendar $calendar, IntlCalendar $other): bool {}

/**
 * Get behavior for handling skipped wall time
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return int One of the constants IntlCalendar::WALLTIME_FIRST, IntlCalendar::WALLTIME_LAST or IntlCalendar::WALLTIME_NEXT_VALID.
 * @since 5.5
 */
function intlcal_get_skipped_wall_time_option(IntlCalendar $calendar): int {}

/**
 * Set behavior for handling repeating wall times at negative timezone offset transitions
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $option One of the constants IntlCalendar::WALLTIME_FIRST or IntlCalendar::WALLTIME_LAST.
 * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
 * @since 5.5
 */
function intlcal_set_repeated_wall_time_option(IntlCalendar $calendar, int $option) {}

/**
 * Set behavior for handling skipped wall times at positive timezone offset transitions
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @param int $option One of the constants IntlCalendar::WALLTIME_FIRST, IntlCalendar::WALLTIME_LAST or IntlCalendar::WALLTIME_NEXT_VALID.
 * @return bool Returns TRUE on success. Failure can only happen due to invalid parameters.
 * @since 5.5
 */
function intlcal_set_skipped_wall_time_option(IntlCalendar $calendar, int $option) {}

/**
 * Create an IntlCalendar from a DateTime object or string
 * @param DateTime|string $datetime A DateTime object or a string that can be passed to  DateTime::__construct().
 * @param null|string $locale
 * @return IntlCalendar|null The created IntlCalendar object or NULL in case of failure. If a string is passed, any exception that occurs inside the DateTime constructor is propagated.
 * @since 5.5
 */
function intlcal_from_date_time(
    DateTime|string $datetime,
    ?string $locale = null
): ?IntlCalendar {}

/**
 * Convert an IntlCalendar into a DateTime object
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return DateTime|false A DateTime object with the same timezone as this object (though using PHP's database instead of ICU's) and the same time, except for the smaller precision (second precision instead of millisecond). Returns FALSE on failure.
 * @since 5.5
 */
function intlcal_to_date_time(IntlCalendar $calendar): DateTime|false {}

/**
 * Get last error code on the object
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return int|false An ICU error code indicating either success, failure or a warning.
 * @since 5.5
 */
function intlcal_get_error_code(IntlCalendar $calendar): int|false {}

/**
 * Get last error message on the object
 * @param IntlCalendar $calendar The calendar object, on the procedural style interface.
 * @return string|false The error message associated with last error that occurred in a function call on this object, or a string indicating the non-existance of an error.
 * @since 5.5
 */
function intlcal_get_error_message(IntlCalendar $calendar): string|false {}

/**
 * Get the number of IDs in the equivalency group that includes the given ID
 * @param string $timezoneId
 * @return int|false
 * @since 5.5
 */
function intltz_count_equivalent_ids(string $timezoneId): int|false {}

/**
 * Create a new copy of the default timezone for this host
 * @return IntlTimeZone
 * @since 5.5
 */
function intlz_create_default() {}

/**
 * @param IntlTimeZone|string|int|float|null $countryOrRawOffset [optional]
 * @return IntlIterator|false
 * @since 5.5
 */
function intltz_create_enumeration($countryOrRawOffset = null): IntlIterator|false {}

/**
 * @param string $timezoneId
 * @return IntlTimeZone|null
 * @since 5.5
 */
function intltz_create_time_zone(string $timezoneId): ?IntlTimeZone {}

/**
 * @param DateTimeZone $timezone
 * @return IntlTimeZone|null
 * @since 5.5
 */
function intltz_from_date_time_zone(DateTimeZone $timezone): ?IntlTimeZone {}

/**
 * Get the canonical system timezone ID or the normalized custom time zone ID for the given time zone ID
 * @param string $timezoneId
 * @param bool &$isSystemId [optional]
 * @return string|false
 * @since 5.5
 */
function intltz_get_canonical_id(string $timezoneId, &$isSystemId = null): string|false {}

/**
 * Get a name of this time zone suitable for presentation to the user
 * @param IntlTimeZone $timezone - The time zone object, on the procedural style interface.
 * @param bool $dst [optional]
 * @param int $style [optional]
 * @param string|null $locale [optional]
 * @return string|false
 * @since 5.5
 */
function intltz_get_display_name(IntlTimeZone $timezone, bool $dst = false, int $style = 2, ?string $locale = null): string|false {}

/**
 * Get the amount of time to be added to local standard time to get local wall clock time
 * @param IntlTimeZone $timezone - The time zone object, on the procedural style interface.
 * @return int
 * @since 5.5
 */
function intltz_get_dst_savings(IntlTimeZone $timezone): int {}

/**
 * Get an ID in the equivalency group that includes the given ID
 * @param string $timezoneId
 * @param int $offset
 * @return string|false
 * @since 5.5
 */
function intltz_get_equivalent_id(string $timezoneId, int $offset): string|false {}

/**
 * Get last error code on the object
 * @param IntlTimeZone $timezone - The time zone object, on the procedural style interface.
 * @return int|false
 * @since 5.5
 */
function intltz_get_error_code(IntlTimeZone $timezone): int|false {}

/**
 * Get last error message on the object
 * @param IntlTimeZone $timezone - The time zone object, on the procedural style interface.
 * @return string|false
 * @since 5.5
 */
function intltz_get_error_message(IntlTimeZone $timezone): string|false {}

/**
 * Create GMT (UTC) timezone
 * @return IntlTimeZone
 * @since 5.5
 */
function intltz_getGMT(): IntlTimeZone {}

/**
 * Get timezone ID
 * @param IntlTimeZone $timezone
 * @return string|false
 * @since 5.5
 */
function intltz_get_id(IntlTimeZone $timezone): string|false {}

/**
 * Get the time zone raw and GMT offset for the given moment in time
 * @param IntlTimeZone $timezone
 * @param float $timestamp
 * @param bool $local
 * @param int &$rawOffset
 * @param int &$dstOffset
 * @return bool
 * @since 5.5
 */
function intltz_get_offset(IntlTimeZone $timezone, float $timestamp, bool $local, &$rawOffset, &$dstOffset): bool {}

/**
 * Get the raw GMT offset (before taking daylight savings time into account
 * @param IntlTimeZone $timezone
 * @return int
 */
function intltz_get_raw_offset(IntlTimeZone $timezone): int {}

/**
 * Get the timezone data version currently used by ICU
 * @return string|false
 * @since 5.5
 */
function intltz_get_tz_data_version(): string|false {}

/**
 * Check if this zone has the same rules and offset as another zone
 * @param IntlTimeZone $timezone
 * @param IntlTimeZone $other
 * @return bool
 * @since 5.5
 */
function intltz_has_same_rules(
    IntlTimeZone $timezone,
    IntlTimeZone $other = null,
    IntlTimeZone $other
): bool {}

/**
 * Convert to DateTimeZone object
 * @param IntlTimeZone $timezone
 * @return DateTimeZone|false
 * @since 5.5
 */
function intltz_to_date_time_zone(IntlTimeZone $timezone): DateTimeZone|false {}

/**
 * Check if this time zone uses daylight savings time
 * @param IntlTimeZone $timezone
 * @return bool
 * @since 5.5
 */
function intltz_use_daylight_time(IntlTimeZone $timezone): bool {}

/**
 * @param DateTimeZone|IntlTimeZone|string|int|null $timezoneOrYear [optional]
 * @param string|null $localeOrMonth [optional]
 * @param int $day [optional]
 * @param int $hour [optional]
 * @param int $minute [optional]
 * @param int $second [optional]
 * @return IntlGregorianCalendar|null
 * @since 5.5
 */
function intlgregcal_create_instance($timezoneOrYear, $localeOrMonth, $day, $hour, $minute, $second): ?IntlGregorianCalendar {}

/**
 * @param IntlGregorianCalendar $calendar
 * @param float $timestamp
 * @return bool
 */
function intlgregcal_set_gregorian_change(IntlGregorianCalendar $calendar, float $timestamp): bool {}

/**
 * @param IntlGregorianCalendar $calendar
 * @return float
 */
function intlgregcal_get_gregorian_change(IntlGregorianCalendar $calendar): float {}

/**
 * @param IntlGregorianCalendar $calendar
 * @param int $year
 * @return bool
 */
function intlgregcal_is_leap_year(IntlGregorianCalendar $calendar, int $year): bool {}

/**
 * Create a resource bundle
 * @param string|null $locale Locale for which the resources should be loaded (locale name, e.g. en_CA).
 * @param string|null $bundle The directory where the data is stored or the name of the .dat file.
 * @param bool $fallback [optional] Whether locale should match exactly or fallback to parent locale is allowed.
 * @return ResourceBundle|null ResourceBundle object or NULL on error.
 */
function resourcebundle_create(?string $locale, ?string $bundle, bool $fallback = true): ?ResourceBundle {}

/**
 * Get data from the bundle
 * @param ResourceBundle $bundle ResourceBundle object.
 * @param string|int $index Data index, must be string or integer.
 * @param bool $fallback Whether locale should match exactly or fallback to parent locale is allowed.
 * @return mixed the data located at the index or NULL on error. Strings, integers and binary data strings are returned as corresponding PHP types, integer array is returned as PHP array. Complex types are returned as ResourceBundle object.
 */
function resourcebundle_get(ResourceBundle $bundle, string|int $index, bool $fallback = true) {}

/**
 * Get number of elements in the bundle
 * @param ResourceBundle $bundle ResourceBundle object.
 * @return int number of elements in the bundle.
 */
function resourcebundle_count(ResourceBundle $bundle): int {}

/**
 * Get supported locales
 * @param string $bundle Path of ResourceBundle for which to get available locales, or empty string for default locales list.
 * @return array|false the list of locales supported by the bundle.
 */
function resourcebundle_locales(string $bundle): array|false {}

/**
 * Get bundle's last error code.
 * @param ResourceBundle $bundle ResourceBundle object.
 * @return int error code from last bundle object call.
 */
function resourcebundle_get_error_code(ResourceBundle $bundle): int {}

/**
 * Get bundle's last error message.
 * @param ResourceBundle $bundle ResourceBundle object.
 * @return string error message from last bundle object's call.
 */
function resourcebundle_get_error_message(ResourceBundle $bundle): string {}

/**
 * Create a transliterator
 * @param string $id The id.
 * @param int $direction The direction, defaults to Transliterator::FORWARD. May also be set to Transliterator::REVERSE.
 * @return Transliterator|null a Transliterator object on success, or NULL on failure.
 * @since 5.4
 */
function transliterator_create(string $id, int $direction = 0): ?Transliterator {}

/**
 * Create transliterator from rules
 * @param string $rules The rules.
 * @param int $direction The direction, defaults to Transliterator::FORWARD. May also be set to Transliterator::REVERSE.
 * @return Transliterator|null a Transliterator object on success, or NULL on failure.
 * @since 5.4
 */
function transliterator_create_from_rules(string $rules, int $direction = 0): ?Transliterator {}

/**
 * Get transliterator IDs
 * @return string[]|false An array of registered transliterator IDs on success, or FALSE on failure.
 * @since 5.4
 */
function transliterator_list_ids(): array|false {}

/**
 * Create an inverse transliterator
 * @param Transliterator $transliterator
 * @return Transliterator|null a Transliterator object on success, or NULL on failure
 * @since 5.4
 */
function transliterator_create_inverse(Transliterator $transliterator): ?Transliterator {}

/**
 * Transliterate a string
 * @param Transliterator|string $transliterator In the procedural version, either a Transliterator or a string from which a Transliterator can be built.
 * @param string $string The string to be transformed.
 * @param int $start The start index (in UTF-16 code units) from which the string will start to be transformed, inclusive. Indexing starts at 0. The text before will be left as is.
 * @param int $end The end index (in UTF-16 code units) until which the string will be transformed, exclusive. Indexing starts at 0. The text after will be left as is.
 * @return string|false The transfomed string on success, or FALSE on failure.
 * @since 5.4
 */
function transliterator_transliterate(Transliterator|string $transliterator, string $string, int $start = 0, int $end = -1): string|false {}

/**
 * Get last error code
 * @param Transliterator $transliterator
 * @return int|false The error code on success, or FALSE if none exists, or on failure.
 * @since 5.4
 */
function transliterator_get_error_code(Transliterator $transliterator) {}

/**
 * Get last error message
 * @param Transliterator $transliterator
 * @return string|false The error code on success, or FALSE if none exists, or on failure.
 * @since 5.4
 */
function transliterator_get_error_message(Transliterator $transliterator) {}

/**
 * Get the last error code
 * @return int Error code returned by the last API function call.
 */
function intl_get_error_code(): int {}

/**
 * Get description of the last error
 * @return string Description of an error occurred in the last API function call.
 */
function intl_get_error_message(): string {}

/**
 * Check whether the given error code indicates failure
 * @param int $errorCode is a value that returned by functions: intl_get_error_code, collator_get_error_code .
 * @return bool TRUE if it the code indicates some failure, and FALSE in case of success or a warning.
 */
function intl_is_failure(int $errorCode): bool {}

/**
 * Get symbolic name for a given error code
 * @param int $errorCode ICU error code.
 * @return string The returned string will be the same as the name of the error code constant.
 */
function intl_error_name(int $errorCode): string {}

/**
 * Gets the Decomposition_Mapping property for the given UTF-8 encoded code point
 * @param string $string The input string, which should be a single, UTF-8 encoded, code point.
 * @param int $form
 * @return string|null Returns a string containing the Decomposition_Mapping property, if present in the UCD. Returns null if there is no Decomposition_Mapping property for the character.
 * @since 7.3
 */
function normalizer_get_raw_decomposition(string $string, int $form = Normalizer::FORM_C): ?string {}

/**
 * Create a new copy of the default timezone for this host
 * @return IntlTimeZone
 * @since 5.5
 */
function intltz_create_default(): IntlTimeZone {}

/**
 * Create GMT (UTC) timezone
 * @return IntlTimeZone
 * @since 5.5
 */
function intltz_get_gmt(): IntlTimeZone {}

/**
 * Get the "unknown" time zone
 * @return IntlTimeZone
 * @since 5.5
 */
function intltz_get_unknown(): IntlTimeZone {}

/**
 * Get an enumeration over system time zone IDs with the given filter conditions
 * @param int $type
 * @param null|string $region
 * @param null|int $rawOffset
 * @return IntlIterator|false
 * @since 5.5
 */
function intltz_create_time_zone_id_enumeration(int $type, ?string $region = null, ?int $rawOffset = null): IntlIterator|false {}

/**
 * Get the region code associated with the given system time zone ID
 * @param string $timezoneId
 * @return string|false
 * @since 5.5
 */
function intltz_get_region(string $timezoneId): string|false {}

/**
 * Set minimal number of days the first week in a year or month can have
 * @param IntlCalendar $calendar
 * @param int $days
 * @return bool
 * @since 5.5
 */
function intlcal_set_minimal_days_in_first_week(IntlCalendar $calendar, int $days) {}

/**
 * Translate a system timezone into a Windows timezone
 *
 * Translates a system timezone (e.g. "America/Los_Angeles") into a Windows timezone (e.g. "Pacific
 * Standard Time").
 * @param string $timezoneId
 * @return string|false Returns the Windows timezone or false on failure.
 */
function intltz_get_windows_id(string $timezoneId): string|false {}

/**
 * Translate a Windows timezone into a system timezone
 *
 * Translates a Windows timezone (e.g. "Pacific Standard Time") into a system timezone (e.g.
 * "America/Los_Angeles").
 * @param string $timezoneId
 * @param string|null $region
 * @return string|false Returns the system timezone or false on failure.
 */
function intltz_get_id_for_windows_id(string $timezoneId, ?string $region = null): string|false {}

/**
 * Split a string into an array
 *
 * This function will return an array of strings, it is a version of str_split with support for
 * grapheme cluster byte characters. If the length parameter is specified, the string is broken down
 * into chunks of the specified length in grapheme clusters (not bytes).
 * @since 8.4
 * @throws \ValueError If length is less than 1, a ValueError will be thrown.
 */
function grapheme_str_split(string $string, int $length = 1): array|false {}

/**
 * Translate a timezone identifier to its IANA equivalent
 *
 * Translates a timezone identifier to its IANA equivalent. For example, "GMT" returns "Etc/GMT",
 * and "US/Eastern" returns "America/New_York".
 * @since  8.4
 */
function intltz_get_iana_id(string $timezoneId): string|false {}

/**
 * @since 8.5
 */
function grapheme_levenshtein(string $string1, string $string2, int $insertion_cost = 1, int $replacement_cost = 1, int $deletion_cost = 1, string $locale = ""): int|false {}

/**
 * Check whether a locale uses a right-to-left writing system
 *
 * Determines whether a locale uses a right-to-left writing system.
 * @since 8.5
 */
function locale_is_right_to_left(string $locale): bool {}

/**
 * @since 8.5
 */
function locale_add_likely_subtags(string $locale): string|false {}

/**
 * @since 8.5
 */
function locale_minimize_subtags(string $locale): string|false {}
