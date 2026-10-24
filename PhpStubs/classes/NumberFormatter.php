<?php

/**
 * Programs store and operate on numbers using a locale-independent binary representation. When
 * displaying or printing a number it is converted to a locale-specific string. For example, the
 * number 12345.67 is "12,345.67" in the US, "12 345,67" in France and "12.345,67" in Germany.
 *
 * By invoking the methods provided by the NumberFormatter class, you can format numbers,
 * currencies, and percentages according to the specified or default locale. NumberFormatter is
 * locale-sensitive so you need to create a new NumberFormatter for each locale. NumberFormatter
 * methods format primitive-type numbers, such as double and output the number as a locale-specific
 * string. For currencies you can use currency ...
 */
class NumberFormatter
{
    public const CURRENCY_ACCOUNTING = 12;

    /**
     * Decimal format defined by pattern
     */
    public const PATTERN_DECIMAL = 0;

    /**
     * Decimal format
     */
    public const DECIMAL = 1;

    /**
     * Currency format
     */
    public const CURRENCY = 2;

    /**
     * Percent format
     */
    public const PERCENT = 3;

    /**
     * Scientific format
     */
    public const SCIENTIFIC = 4;

    /**
     * Spellout rule-based format
     */
    public const SPELLOUT = 5;

    /**
     * Ordinal rule-based format
     */
    public const ORDINAL = 6;

    /**
     * Duration rule-based format
     */
    public const DURATION = 7;

    /**
     * Rule-based format defined by pattern
     */
    public const PATTERN_RULEBASED = 9;

    /**
     * Alias for PATTERN_DECIMAL
     */
    public const IGNORE = 0;

    /**
     * Default format for the locale
     */
    public const DEFAULT_STYLE = 1;

    /**
     * Rounding mode to round towards positive infinity.
     */
    public const ROUND_CEILING = 0;

    /**
     * Rounding mode to round towards negative infinity.
     */
    public const ROUND_FLOOR = 1;

    /**
     * Rounding mode to round towards zero.
     */
    public const ROUND_DOWN = 2;

    /**
     * Rounding mode to round away from zero.
     */
    public const ROUND_UP = 3;

    /**
     * Rounding mode to round towards the "nearest neighbor" unless both
     * neighbors are equidistant, in which case, round towards the even
     * neighbor.
     */
    public const ROUND_HALFEVEN = 4;

    /**
     * Rounding mode to round towards "nearest neighbor" unless both neighbors
     * are equidistant, in which case round down.
     */
    public const ROUND_HALFDOWN = 5;

    /**
     * Rounding mode to round towards "nearest neighbor" unless both neighbors
     * are equidistant, in which case round up.
     */
    public const ROUND_HALFUP = 6;

    /**
     * Pad characters inserted before the prefix.
     */
    public const PAD_BEFORE_PREFIX = 0;

    /**
     * Pad characters inserted after the prefix.
     */
    public const PAD_AFTER_PREFIX = 1;

    /**
     * Pad characters inserted before the suffix.
     */
    public const PAD_BEFORE_SUFFIX = 2;

    /**
     * Pad characters inserted after the suffix.
     */
    public const PAD_AFTER_SUFFIX = 3;

    /**
     * Parse integers only.
     */
    public const PARSE_INT_ONLY = 0;

    /**
     * Use grouping separator.
     */
    public const GROUPING_USED = 1;

    /**
     * Always show decimal point.
     */
    public const DECIMAL_ALWAYS_SHOWN = 2;

    /**
     * Maximum integer digits.
     */
    public const MAX_INTEGER_DIGITS = 3;

    /**
     * Minimum integer digits.
     */
    public const MIN_INTEGER_DIGITS = 4;

    /**
     * Integer digits.
     */
    public const INTEGER_DIGITS = 5;

    /**
     * Maximum fraction digits.
     */
    public const MAX_FRACTION_DIGITS = 6;

    /**
     * Minimum fraction digits.
     */
    public const MIN_FRACTION_DIGITS = 7;

    /**
     * Fraction digits.
     */
    public const FRACTION_DIGITS = 8;

    /**
     * Multiplier.
     */
    public const MULTIPLIER = 9;

    /**
     * Grouping size.
     */
    public const GROUPING_SIZE = 10;

    /**
     * Rounding Mode.
     */
    public const ROUNDING_MODE = 11;

    /**
     * Rounding increment.
     */
    public const ROUNDING_INCREMENT = 12;

    /**
     * The width to which the output of format() is padded.
     */
    public const FORMAT_WIDTH = 13;

    /**
     * The position at which padding will take place. See pad position
     * constants for possible argument values.
     */
    public const PADDING_POSITION = 14;

    /**
     * Secondary grouping size.
     */
    public const SECONDARY_GROUPING_SIZE = 15;

    /**
     * Use significant digits.
     */
    public const SIGNIFICANT_DIGITS_USED = 16;

    /**
     * Minimum significant digits.
     */
    public const MIN_SIGNIFICANT_DIGITS = 17;

    /**
     * Maximum significant digits.
     */
    public const MAX_SIGNIFICANT_DIGITS = 18;

    /**
     * Lenient parse mode used by rule-based formats.
     */
    public const LENIENT_PARSE = 19;

    /**
     * Positive prefix.
     */
    public const POSITIVE_PREFIX = 0;

    /**
     * Positive suffix.
     */
    public const POSITIVE_SUFFIX = 1;

    /**
     * Negative prefix.
     */
    public const NEGATIVE_PREFIX = 2;

    /**
     * Negative suffix.
     */
    public const NEGATIVE_SUFFIX = 3;

    /**
     * The character used to pad to the format width.
     */
    public const PADDING_CHARACTER = 4;

    /**
     * The ISO currency code.
     */
    public const CURRENCY_CODE = 5;

    /**
     * The default rule set. This is only available with rule-based
     * formatters.
     */
    public const DEFAULT_RULESET = 6;

    /**
     * The public rule sets. This is only available with rule-based
     * formatters. This is a read-only attribute. The public rulesets are
     * returned as a single string, with each ruleset name delimited by ';'
     * (semicolon).
     */
    public const PUBLIC_RULESETS = 7;

    /**
     * The decimal separator.
     */
    public const DECIMAL_SEPARATOR_SYMBOL = 0;

    /**
     * The grouping separator.
     */
    public const GROUPING_SEPARATOR_SYMBOL = 1;

    /**
     * The pattern separator.
     */
    public const PATTERN_SEPARATOR_SYMBOL = 2;

    /**
     * The percent sign.
     */
    public const PERCENT_SYMBOL = 3;

    /**
     * Zero.
     */
    public const ZERO_DIGIT_SYMBOL = 4;

    /**
     * Character representing a digit in the pattern.
     */
    public const DIGIT_SYMBOL = 5;

    /**
     * The minus sign.
     */
    public const MINUS_SIGN_SYMBOL = 6;

    /**
     * The plus sign.
     */
    public const PLUS_SIGN_SYMBOL = 7;

    /**
     * The currency symbol.
     */
    public const CURRENCY_SYMBOL = 8;

    /**
     * The international currency symbol.
     */
    public const INTL_CURRENCY_SYMBOL = 9;

    /**
     * The monetary separator.
     */
    public const MONETARY_SEPARATOR_SYMBOL = 10;

    /**
     * The exponential symbol.
     */
    public const EXPONENTIAL_SYMBOL = 11;

    /**
     * Per mill symbol.
     */
    public const PERMILL_SYMBOL = 12;

    /**
     * Escape padding character.
     */
    public const PAD_ESCAPE_SYMBOL = 13;

    /**
     * Infinity symbol.
     */
    public const INFINITY_SYMBOL = 14;

    /**
     * Not-a-number symbol.
     */
    public const NAN_SYMBOL = 15;

    /**
     * Significant digit symbol.
     */
    public const SIGNIFICANT_DIGIT_SYMBOL = 16;

    /**
     * The monetary grouping separator.
     */
    public const MONETARY_GROUPING_SEPARATOR_SYMBOL = 17;

    /**
     * Derive the type from variable type
     */
    public const TYPE_DEFAULT = 0;

    /**
     * Format/parse as 32-bit integer
     */
    public const TYPE_INT32 = 1;

    /**
     * Format/parse as 64-bit integer
     */
    public const TYPE_INT64 = 2;

    /**
     * Format/parse as floating point value
     */
    public const TYPE_DOUBLE = 3;

    /**
     * Format/parse as currency value
     * @deprecated 8.3
     */
    public const TYPE_CURRENCY = 4;

    /**
     * @since 8.4
     */
    public const ROUND_TOWARD_ZERO = 2;

    /**
     * @since 8.4
     */
    public const ROUND_AWAY_FROM_ZERO = 3;

    /**
     * @since 8.4
     */
    public const ROUND_HALFODD = 8;

    /**
     * @since 8.5
     */
    public const DECIMAL_COMPACT_SHORT = 14;

    /**
     * @since 8.5
     */
    public const DECIMAL_COMPACT_LONG = 15;

    /**
     * @since 8.5
     */
    public const CURRENCY_ISO = 10;

    /**
     * @since 8.5
     */
    public const CURRENCY_PLURAL = 11;

    /**
     * @since 8.5
     */
    public const CASH_CURRENCY = 13;

    /**
     * @since 8.5
     */
    public const CURRENCY_STANDARD = 16;

    /**
     * Create a number formatter
     *
     * Creates a number formatter.
     * @param string $locale Locale in which the number would be formatted (locale name, e.g. en_CA).
     * @param int $style Style of the formatting, one of the format style constants. If NumberFormatter::PATTERN_DECIMAL or NumberFormatter::PATTERN_RULEBASED is passed then the number format is opened using the given pattern, which must conform to the syntax described in ICU DecimalFormat documentation ...
     * @param string $pattern [optional]
     */
    public function __construct(
        $locale,
        $style,
        $pattern = null
    ) {}

    /**
     * Create a number formatter
     * @param string $locale Locale in which the number would be formatted (locale name, e.g. en_CA).
     * @param int $style Style of the formatting, one of the format style constants. If NumberFormatter::PATTERN_DECIMAL or NumberFormatter::PATTERN_RULEBASED is passed then the number format is opened using the given pattern, which must conform to the syntax described in ICU DecimalFormat documentation ...
     * @param string $pattern [optional] Pattern string if the chosen style requires a pattern.
     * @return NumberFormatter|false NumberFormatter object or FALSE on error.
     */
    public static function create(
        $locale,
        $style,
        $pattern = null
    ): ?NumberFormatter {}

    /**
     * Format a number
     * @param int|float $num The value to format. Can be integer or float, other values will be converted to a numeric value.
     * @param int $type [optional] The formatting type to use.
     * @return string|false the string containing formatted value, or FALSE on error.
     */
    public function format(
        $num,
        $type = 0
    ): string|false {}

    /**
     * Parse a number
     * @param string $string The string to parse for the number.
     * @param int $type [optional] The formatting type to use. By default, NumberFormatter::TYPE_DOUBLE is used.
     * @param int &$offset [optional] Offset in the string at which to begin parsing. On return, this value will hold the offset at which parsing ended.
     * @return mixed The value of the parsed number or FALSE on error.
     */
    public function parse(
        $string,
        $type = NumberFormatter::TYPE_DOUBLE,
        &$offset = null
    ): int|float|false {}

    /**
     * Format a currency value
     * @param float $amount The numeric currency value.
     * @param string $currency The 3-letter ISO 4217 currency code indicating the currency to use.
     * @return string|false String representing the formatted currency value.
     */
    public function formatCurrency(
        $amount,
        $currency
    ): string|false {}

    /**
     * Parse a currency number
     * @param string $string
     * @param string &$currency Parameter to receive the currency name (3-letter ISO 4217 currency code).
     * @param int &$offset [optional] Offset in the string at which to begin parsing. On return, this value will hold the offset at which parsing ended.
     * @return float|false The parsed numeric value or FALSE on error.
     */
    public function parseCurrency($string, &$currency, &$offset = null): float|false {}

    /**
     * Set an attribute
     * @param int $attribute Attribute specifier - one of the numeric attribute constants.
     * @param int $value The attribute value.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setAttribute(
        $attribute,
        $value
    ): bool {}

    /**
     * Get an attribute
     * @param int $attribute Attribute specifier - one of the numeric attribute constants.
     * @return int|float|false Return attribute value on success, or FALSE on error.
     */
    public function getAttribute($attribute): int|float|false {}

    /**
     * Set a text attribute
     * @param int $attribute Attribute specifier - one of the text attribute constants.
     * @param string $value Text for the attribute value.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setTextAttribute(
        $attribute,
        $value
    ): bool {}

    /**
     * Get a text attribute
     * @param int $attribute Attribute specifier - one of the text attribute constants.
     * @return string|false Return attribute value on success, or FALSE on error.
     */
    public function getTextAttribute($attribute): string|false {}

    /**
     * Set a symbol value
     * @param int $symbol Symbol specifier, one of the format symbol constants.
     * @param string $value Text for the symbol.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setSymbol(
        $symbol,
        $value
    ): bool {}

    /**
     * Get a symbol value
     * @param int $symbol Symbol specifier, one of the format symbol constants.
     * @return string|false The symbol string or FALSE on error.
     */
    public function getSymbol($symbol): string|false {}

    /**
     * Set formatter pattern
     * @param string $pattern Pattern in syntax described in ICU DecimalFormat documentation.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setPattern($pattern): bool {}

    /**
     * Get formatter pattern
     * @return string|false Pattern string that is used by the formatter, or FALSE if an error happens.
     */
    public function getPattern(): string|false {}

    /**
     * Get formatter locale
     * @param int $type [optional] You can choose between valid and actual locale ( Locale::VALID_LOCALE, Locale::ACTUAL_LOCALE, respectively). The default is the actual locale.
     * @return string|false The locale name used to create the formatter.
     */
    public function getLocale(
        $type = 0
    ): string|false {}

    /**
     * Get formatter's last error code.
     * @return int error code from last formatter call.
     */
    public function getErrorCode(): int {}

    /**
     * Get formatter's last error message.
     * @return string error message from last formatter call.
     */
    public function getErrorMessage(): string {}
}
