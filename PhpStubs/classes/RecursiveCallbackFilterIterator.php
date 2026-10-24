<?php

/**
 * RecursiveCallbackFilterIterator from a RecursiveIterator
 * @since 5.4
 */
class RecursiveCallbackFilterIterator extends CallbackFilterIterator implements RecursiveIterator
{
    /**
     * Create a RecursiveCallbackFilterIterator from a RecursiveIterator
     * @param RecursiveIterator $iterator The recursive iterator to be filtered.
     * @param callable $callback The callback, which should return TRUE to accept the current item or FALSE otherwise. See Examples. May be any valid callable value.
     */
    public function __construct(
        RecursiveIterator $iterator,
        callable $callback
    ) {}

    /**
     * Check whether the inner iterator's current element has children
     * @return bool Returns TRUE if the current element has children, FALSE otherwise.
     */
    public function hasChildren(): bool {}

    /**
     * Returns an iterator for the current entry.
     * @return RecursiveCallbackFilterIterator containing the children.
     */
    public function getChildren(): RecursiveCallbackFilterIterator {}
}
