<?php

/**
 * This abstract iterator filters out unwanted values for a RecursiveIterator.
 * This class should be extended to implement custom filters.
 * The RecursiveFilterIterator::accept must be implemented in the subclass.
 */
abstract class RecursiveFilterIterator extends FilterIterator implements RecursiveIterator
{
    /**
     * Create a RecursiveFilterIterator from a RecursiveIterator
     * @param RecursiveIterator $iterator The RecursiveIterator to be filtered.
     */
    public function __construct(RecursiveIterator $iterator) {}

    /**
     * Check whether the inner iterator's current element has children
     * @return bool true if the inner iterator has children, otherwise false
     */
    public function hasChildren(): bool {}

    /**
     * Return the inner iterator's children contained in a RecursiveFilterIterator
     * @return RecursiveFilterIterator|null containing the inner iterator's children.
     */
    public function getChildren(): ?RecursiveFilterIterator {}
}
