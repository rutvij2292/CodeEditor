<?php

/**
 * This iterator cannot be rewinded.
 */
class NoRewindIterator extends IteratorIterator
{
    /**
     * Construct a NoRewindIterator
     * @param Iterator $iterator The iterator being used.
     */
    public function __construct(Iterator $iterator) {}

    /**
     * Prevents the rewind operation on the inner iterator.
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Validates the iterator
     * @return bool true on success or false on failure.
     */
    public function valid(): bool {}

    /**
     * Get the current key
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Get the current value
     * @return mixed The current value.
     */
    public function current(): mixed {}

    /**
     * Forward to the next element
     * @return void
     */
    public function next(): void {}

    /**
     * Get the inner iterator
     * @return Iterator The inner iterator, as passed to NoRewindIterator::__construct.
     */
    public function getInnerIterator(): ?Iterator {}
}
