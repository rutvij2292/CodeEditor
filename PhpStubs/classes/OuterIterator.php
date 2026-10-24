<?php

/**
 * Classes implementing OuterIterator can be used to iterate
 * over iterators.
 */
interface OuterIterator extends Iterator
{
    /**
     * Returns the inner iterator for the current entry.
     * @return Iterator|null The inner iterator for the current entry.
     */
    public function getInnerIterator(): ?Iterator;
}
