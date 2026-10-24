<?php

/**
 * Class to ease implementing IteratorAggregate for internal classes.
 * @since 8.0
 */
final class InternalIterator implements Iterator
{
    /**
     * Private constructor to disallow direct instantiation
     */
    private function __construct() {}

    /**
     * Return the current element
     *
     * Returns the current element.
     * @return mixed Returns the current element.
     */
    public function current(): mixed {}

    /**
     * Move forward to next element
     *
     * Moves the current position to the next element.
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Return the key of the current element
     *
     * Returns the key of the current element.
     * @return mixed Returns the key of the current element.
     */
    public function key(): mixed {}

    /**
     * Check if current position is valid
     *
     * Checks if current position is valid.
     * @return bool Returns whether the current position is valid.
     */
    public function valid(): bool {}

    /**
     * Rewind the Iterator to the first element
     *
     * Rewinds back to the first element of the Iterator.
     * @return void No value is returned.
     */
    public function rewind(): void {}
}
