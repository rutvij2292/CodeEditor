<?php

/**
 * The LimitIterator class allows iteration over
 * a limited subset of items in an Iterator.
 */
class LimitIterator extends IteratorIterator
{
    /**
     * Construct a LimitIterator
     * @param Iterator $iterator The iterator to limit.
     * @param int $offset [optional] The offset to start at. Must be zero or greater.
     * @param int $limit [optional] The number of items to iterate. Must be -1 or greater. -1, the default, means no limit.
     * @throws \ValueError Throws a ValueError if the offset is less than 0 or the limit is less than -1.
     */
    public function __construct(
        Iterator $iterator,
        int $offset = 0,
        int $limit = -1
    ) {}

    /**
     * Rewind the iterator to the specified starting offset
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Check whether the current element is valid
     * @return bool true on success or false on failure.
     */
    public function valid(): bool {}

    /**
     * Get current key
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Get current element
     * @return mixed the current element or null if there is none.
     */
    public function current(): mixed {}

    /**
     * Move the iterator forward
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Seek to the given position
     * @param int $offset The position to seek to.
     * @return int the offset position after seeking.
     * @throws \OutOfBoundsException Throws an OutOfBoundsException if the position is outside of the limits specified in LimitIterator::__construct.
     */
    public function seek(int $offset): int {}

    /**
     * Return the current position
     * @return int The current position.
     */
    public function getPosition(): int {}

    /**
     * Get inner iterator
     * @return Iterator The inner iterator passed to LimitIterator::__construct.
     */
    public function getInnerIterator(): ?Iterator {}
}
