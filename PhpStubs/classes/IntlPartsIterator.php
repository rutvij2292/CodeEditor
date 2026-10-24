<?php

/**
 * Objects of this class can be obtained from IntlBreakIterator objects. While the break iterators
 * provide a sequence of boundary positions when iterated, IntlPartsIterator objects provide, as a
 * convenience, the text fragments comprehended between two successive boundaries.
 *
 * The keys may represent the offset of the left boundary, right boundary, or they may just the
 * sequence of non-negative integers. See IntlBreakIterator::getPartsIterator.
 * @since 5.5
 */
class IntlPartsIterator extends IntlIterator implements Iterator
{
    public const KEY_SEQUENTIAL = 0;

    public const KEY_LEFT = 1;

    public const KEY_RIGHT = 2;

    /**
     * Get IntlBreakIterator backing this parts iterator
     * @return IntlBreakIterator
     */
    public function getBreakIterator(): IntlBreakIterator {}

    /**
     * @since 8.1
     */
    public function getRuleStatus(): int {}
}
