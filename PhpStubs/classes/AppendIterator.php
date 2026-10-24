<?php

/**
 * An Iterator that iterates over several iterators one after the other.
 */
class AppendIterator extends IteratorIterator
{
    /**
     * Constructs an AppendIterator
     */
    public function __construct() {}

    /**
     * Appends an iterator
     * @param Iterator $iterator The iterator to append.
     * @return void No value is returned.
     */
    public function append(Iterator $iterator): void {}

    /**
     * Rewinds the Iterator
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Checks validity of the current element
     * @return bool true on success or false on failure.
     */
    public function valid(): bool {}

    /**
     * Gets the current key
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Gets the current value
     * @return mixed The current value if it is valid or null otherwise.
     */
    public function current(): mixed {}

    /**
     * Moves to the next element
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Gets an inner iterator
     * @return Iterator the current inner Iterator.
     */
    public function getInnerIterator(): ?Iterator {}

    /**
     * Gets an index of iterators
     * @return int|null The index of iterators.
     */
    public function getIteratorIndex(): ?int {}

    /**
     * The getArrayIterator method
     * @return ArrayIterator containing the appended iterators.
     */
    public function getArrayIterator(): ArrayIterator {}
}
