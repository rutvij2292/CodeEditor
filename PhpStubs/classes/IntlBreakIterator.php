<?php

/**
 * A “break iterator” is an ICU object that exposes methods for locating boundaries in text
 * (e.g. word or sentence boundaries). The PHP IntlBreakIterator serves as the base class for all
 * types of ICU break iterators. Where extra functionality is available, the intl extension may
 * expose the ICU break iterator with suitable subclasses, such as IntlRuleBasedBreakIterator or
 * IntlCodePointBreakIterator.
 *
 * This class implements IteratorAggregate. Traversing an IntlBreakIterator yields non-negative
 * integer values representing the successive locations of the text boundaries, expressed as UTF-8
 * code units (byte) counts, taken from the beginning of the text (which has the location 0). The
 * keys yielded by ...
 * @since 5.5
 */
class IntlBreakIterator implements IteratorAggregate
{
    public const DONE = -1;

    public const WORD_NONE = 0;

    public const WORD_NONE_LIMIT = 100;

    public const WORD_NUMBER = 100;

    public const WORD_NUMBER_LIMIT = 200;

    public const WORD_LETTER = 200;

    public const WORD_LETTER_LIMIT = 300;

    public const WORD_KANA = 300;

    public const WORD_KANA_LIMIT = 400;

    public const WORD_IDEO = 400;

    public const WORD_IDEO_LIMIT = 500;

    public const LINE_SOFT = 0;

    public const LINE_SOFT_LIMIT = 100;

    public const LINE_HARD = 100;

    public const LINE_HARD_LIMIT = 200;

    public const SENTENCE_TERM = 0;

    public const SENTENCE_TERM_LIMIT = 100;

    public const SENTENCE_SEP = 100;

    public const SENTENCE_SEP_LIMIT = 200;

    /**
     * Private constructor for disallowing instantiation
     */
    private function __construct() {}

    /**
     * Create break iterator for boundaries of combining character sequences
     * @param string $locale
     * @return IntlBreakIterator|null
     */
    public static function createCharacterInstance($locale = null): ?IntlBreakIterator {}

    /**
     * Create break iterator for boundaries of code points
     * @return IntlCodePointBreakIterator
     */
    public static function createCodePointInstance(): IntlCodePointBreakIterator {}

    /**
     * Create break iterator for logically possible line breaks
     * @param string $locale [optional]
     * @return IntlBreakIterator|null
     */
    public static function createLineInstance($locale = null): ?IntlBreakIterator {}

    /**
     * Create break iterator for sentence breaks
     * @param string $locale [optional]
     * @return IntlBreakIterator|null
     */
    public static function createSentenceInstance($locale = null): ?IntlBreakIterator {}

    /**
     * Create break iterator for title-casing breaks
     * @param string $locale [optional]
     * @return IntlBreakIterator|null
     */
    public static function createTitleInstance($locale = null): ?IntlBreakIterator {}

    /**
     * Create break iterator for word breaks
     * @param string $locale [optional]
     * @return IntlBreakIterator|null
     */
    public static function createWordInstance($locale = null): ?IntlBreakIterator {}

    /**
     * Get index of current position
     * @return int
     */
    public function current(): int {}

    /**
     * Set position to the first character in the text
     */
    public function first(): int {}

    /**
     * Advance the iterator to the first boundary following specified offset
     * @param int $offset
     */
    public function following($offset): int {}

    /**
     * Get last error code on the object
     * @return int
     */
    public function getErrorCode(): int {}

    /**
     * Get last error message on the object
     * @return string
     */
    public function getErrorMessage(): string {}

    /**
     * Get the locale associated with the object
     * @param int $type
     */
    public function getLocale($type): string|false {}

    /**
     * Create iterator for navigating fragments between boundaries
     * @param int|string $type [optional] Optional key type. Possible values are: IntlPartsIterator::KEY_SEQUENTIAL - The default. Sequentially increasing integers used as key. IntlPartsIterator::KEY_LEFT - Byte offset left of current part used as key. IntlPartsIterator::KEY_RIGHT - Byte offset right of ...
     */
    public function getPartsIterator(
        $type = IntlPartsIterator::KEY_SEQUENTIAL
    ): IntlPartsIterator {}

    /**
     * Get the text being scanned
     */
    public function getText(): ?string {}

    /**
     * Tell whether an offset is a boundary's offset
     * @param int $offset
     */
    public function isBoundary($offset): bool {}

    /**
     * Set the iterator position to index beyond the last character
     * @return int
     */
    public function last(): int {}

    /**
     * @param int $offset [optional]
     * @return int
     */
    public function next($offset = null): int {}

    /**
     * @param int $offset
     */
    public function preceding($offset): int {}

    /**
     * Set the iterator position to the boundary immediately before the current
     * @return int
     */
    public function previous(): int {}

    /**
     * Set the text being scanned
     * @param string $text
     */
    public function setText($text) {}

    /**
     * @since 8.0
     * @return Iterator
     */
    public function getIterator(): Iterator {}
}
