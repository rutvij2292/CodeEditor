<?php

/**
 * This abstract iterator filters out unwanted values. This class should be extended to
 * implement custom iterator filters. The FilterIterator::accept
 * must be implemented in the subclass.
 */
abstract class FilterIterator extends IteratorIterator
{
    /**
     * Check whether the current element of the iterator is acceptable
     * @return bool true if the current element is acceptable, otherwise false.
     */
    abstract public function accept(): bool;

    /**
     * Construct a filterIterator
     * @param Iterator $iterator The iterator that is being filtered.
     */
    public function __construct(Iterator $iterator) {}

    /**
     * Rewind the iterator
     * @return void
     */
    public function rewind(): void {}

    /**
     * Check whether the current element is valid
     * @return bool true if the current element is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Get the current key
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Get the current element value
     * @return mixed The current element value.
     */
    public function current(): mixed {}

    /**
     * Move the iterator forward
     * @return void
     */
    public function next(): void {}

    /**
     * Get the inner iterator
     * @return Iterator The inner iterator.
     */
    public function getInnerIterator(): ?Iterator {}
}
