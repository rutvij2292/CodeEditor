<?php

/**
 * ...
 */
class RecursiveCachingIterator extends CachingIterator implements RecursiveIterator
{
    /**
     * Constructs a new RecursiveCachingIterator.
     * @param Iterator $iterator The iterator to cache.
     * @param int $flags [optional] A bitmask of flags. See CachingIterator class constants for details.
     */
    public function __construct(Iterator $iterator, int $flags = CachingIterator::CALL_TOSTRING) {}

    /**
     * Check whether the current element of the inner iterator has children
     * @return bool true if the inner iterator has children, otherwise false
     */
    public function hasChildren(): bool {}

    /**
     * Return the inner iterator's children as a RecursiveCachingIterator
     * @return RecursiveCachingIterator|null The inner iterator's children, as a RecursiveCachingIterator.
     */
    public function getChildren(): ?RecursiveCachingIterator {}
}
