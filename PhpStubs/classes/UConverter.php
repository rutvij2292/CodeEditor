<?php

class UConverter
{
    public const REASON_UNASSIGNED = 0;

    public const REASON_ILLEGAL = 1;

    public const REASON_IRREGULAR = 2;

    public const REASON_RESET = 3;

    public const REASON_CLOSE = 4;

    public const REASON_CLONE = 5;

    public const UNSUPPORTED_CONVERTER = -1;

    public const SBCS = 0;

    public const DBCS = 1;

    public const MBCS = 2;

    public const LATIN_1 = 3;

    public const UTF8 = 4;

    public const UTF16_BigEndian = 5;

    public const UTF16_LittleEndian = 6;

    public const UTF32_BigEndian = 7;

    public const UTF32_LittleEndian = 8;

    public const EBCDIC_STATEFUL = 9;

    public const ISO_2022 = 10;

    public const LMBCS_1 = 11;

    public const LMBCS_2 = 12;

    public const LMBCS_3 = 13;

    public const LMBCS_4 = 14;

    public const LMBCS_5 = 15;

    public const LMBCS_6 = 16;

    public const LMBCS_8 = 17;

    public const LMBCS_11 = 18;

    public const LMBCS_16 = 19;

    public const LMBCS_17 = 20;

    public const LMBCS_18 = 21;

    public const LMBCS_19 = 22;

    public const LMBCS_LAST = 22;

    public const HZ = 23;

    public const SCSU = 24;

    public const ISCII = 25;

    public const US_ASCII = 26;

    public const UTF7 = 27;

    public const BOCU1 = 28;

    public const UTF16 = 29;

    public const UTF32 = 30;

    public const CESU8 = 31;

    public const IMAP_MAILBOX = 32;

    /**
     * Create UConverter object
     * @param string $destination_encoding
     * @param string $source_encoding
     */
    public function __construct(
        $destination_encoding = null,
        $source_encoding = null
    ) {}

    /**
     * Convert string from one charset to anothe
     * @param string $str
     * @param bool $reverse [optional]
     * @return string|false
     */
    public function convert(
        $str,
        $reverse = false
    ): string|false {}

    /**
     * Default "from" callback function
     * @param int $reason
     * @param array $source
     * @param int $codePoint
     * @param int &$error
     * @return array|string|int|null
     */
    public function fromUCallback(
        $reason,
        $source,
        $codePoint,
        &$error
    ): array|string|int|null {}

    /**
     * Get the aliases of the given name
     * @param string $name
     * @return array|false|null
     */
    public static function getAliases(
        $name = '',
        $name
    ): array|false|null {}

    /**
     * Get the available canonical converter names
     * @return array
     */
    public static function getAvailable(): array {}

    /**
     * Get the destination encoding
     * @return string|false|null
     */
    public function getDestinationEncoding(): string|false|null {}

    /**
     * Get the destination converter type
     * @return int|false|null
     */
    public function getDestinationType(): int|false|null {}

    /**
     * Get last error code on the object
     * @return int
     */
    public function getErrorCode(): int {}

    /**
     * Get last error message on the object
     * @return string|null
     */
    public function getErrorMessage(): ?string {}

    /**
     * Get the source encoding
     * @return string|false|null
     */
    public function getSourceEncoding(): string|false|null {}

    /**
     * Get the source convertor type
     * @return int|false|null
     */
    public function getSourceType(): int|false|null {}

    /**
     * Get standards associated to converter names
     * @return array|null
     */
    public static function getStandards(): ?array {}

    /**
     * Get substitution chars
     * @return string|false|null
     */
    public function getSubstChars(): string|false|null {}

    /**
     * Get string representation of the callback reason
     * @param int $reason
     * @return string
     */
    public static function reasonText(
        $reason = 0,
        int $reason
    ): string {}

    /**
     * Set the destination encoding
     * @param string $encoding
     * @return bool
     */
    public function setDestinationEncoding($encoding): bool {}

    /**
     * Set the source encoding
     * @param string $encoding
     * @return bool
     */
    public function setSourceEncoding($encoding): bool {}

    /**
     * Set the substitution chars
     * @param string $chars
     * @return bool
     */
    public function setSubstChars($chars): bool {}

    /**
     * Default "to" callback function
     * @param int $reason
     * @param string $source
     * @param string $codeUnits
     * @param int &$error
     * @return array|string|int|null
     */
    public function toUCallback(
        $reason,
        $source,
        $codeUnits,
        &$error
    ): array|string|int|null {}

    /**
     * Convert string from one charset to another
     * @param string $str The string to be converted.
     * @param string $toEncoding The desired encoding of the result.
     * @param string $fromEncoding The current encoding used to interpret str.
     * @param array|null $options An optional array, which may contain the following keys: 'to_subst' - the substitution character to use in place of any character of str which cannot be encoded in toEncoding. If specified, it must represent a single character in the target encoding.
     * @return string|false Returns the converted string or false on failure.
     */
    public static function transcode(
        $str,
        $toEncoding,
        $fromEncoding,
        $options = null
    ): string|false {}
}
