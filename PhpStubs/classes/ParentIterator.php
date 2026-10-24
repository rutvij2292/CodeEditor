<?php

/**
 * This extended FilterIterator allows a recursive iteration using RecursiveIteratorIterator that only shows those elements which have children.
 */
class ParentIterator extends RecursiveFilterIterator
{
    /**
     * Determines acceptability
     * @return bool true if the current element is acceptable, otherwise false.
     */
    public function accept(): bool {}

    /**
     * Constructs a ParentIterator
     * @param RecursiveIterator $iterator The iterator being constructed upon.
     */
    public function __construct(RecursiveIterator $iterator) {}

    /**
     * Check whether the inner iterator's current element has children
     * @return bool true if the inner iterator has children, otherwise false
     */
    public function hasChildren(): bool {}

    /**
     * Return the inner iterator's children contained in a RecursiveFilterIterator
     * @return ParentIterator containing the inner iterator's children.
     */
    public function getChildren(): ?RecursiveFilterIterator {}
}
