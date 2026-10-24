<?php

/**
 * This break iterator identifies the boundaries between UTF-8 code points.
 */
class IntlCodePointBreakIterator extends IntlBreakIterator implements Traversable
{
    /**
     * Get last code point passed over after advancing or receding the iterator
     * @return int
     */
    public function getLastCodePoint(): int {}
}
