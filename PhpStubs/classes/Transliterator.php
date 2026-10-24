<?php

/**
 * Transliterator provides transliteration of strings.
 * @since 5.4
 */
class Transliterator
{
    public const FORWARD = 0;

    public const REVERSE = 1;

    /**
     * @since 5.4
     * @removed 8.2
     */
    public string $id;

    /**
     * @since 8.2 Starting 8.2 $id is readonly to unlock subclassing it
     */
    public readonly string $id;

    /**
     * Private constructor to deny instantiation
     */
    final private function __construct() {}

    /**
     * Create a transliterator
     * @param string $id The id.
     * @param int $direction [optional] The direction, defaults to Transliterator::FORWARD. May also be set to Transliterator::REVERSE.
     * @return Transliterator|null a Transliterator object on success, or NULL on failure.
     */
    public static function create(
        $id,
        $direction = 0
    ): ?Transliterator {}

    /**
     * Create transliterator from rules
     * @param string $rules The rules.
     * @param int $direction [optional] The direction, defaults to Transliterator::FORWARD. May also be set to Transliterator::REVERSE.
     * @return Transliterator|null a Transliterator object on success, or NULL on failure.
     */
    public static function createFromRules(
        $rules,
        $direction = 0
    ): ?Transliterator {}

    /**
     * Create an inverse transliterator
     * @return Transliterator|null a Transliterator object on success, or NULL on failure
     */
    public function createInverse(): ?Transliterator {}

    /**
     * Get transliterator IDs
     * @return array|false An array of registered transliterator IDs on success, or FALSE on failure.
     */
    public static function listIDs(): array|false {}

    /**
     * Transliterate a string
     * @param string $string The string to be transformed.
     * @param int $start [optional] The start index (in UTF-16 code units) from which the string will start to be transformed, inclusive. Indexing starts at 0. The text before will be left as is.
     * @param int $end [optional] The end index (in UTF-16 code units) until which the string will be transformed, exclusive. Indexing starts at 0. The text after will be left as is.
     * @return string|false The transfomed string on success, or FALSE on failure.
     */
    public function transliterate(
        $string,
        $start = 0,
        $end = -1
    ): string|false {}

    /**
     * Get last error code
     * @return int|false The error code on success, or FALSE if none exists, or on failure.
     */
    public function getErrorCode() {}

    /**
     * Get last error message
     * @return string|false The error code on success, or FALSE if none exists, or on failure.
     */
    public function getErrorMessage() {}
}
