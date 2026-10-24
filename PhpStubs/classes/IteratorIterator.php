<?php

/**
 * This iterator wrapper allows the conversion of anything that is
 * Traversable into an Iterator.
 * It is important to understand that most classes that do not implement
 * Iterators have reasons as most likely they do not allow the full
 * Iterator feature set. If so, techniques should be provided to prevent
 * misuse, otherwise expect exceptions or fatal errors.
 */
class IteratorIterator implements OuterIterator
{
    /**
     * Create an iterator from anything that is traversable
     * @param Traversable $iterator The traversable iterator.
     * @param string|null $class [optional]
     */
    public function __construct(Traversable $iterator, ?string $class = null) {}

    /**
     * Get the inner iterator
     * @return Iterator|null The inner iterator as passed to IteratorIterator::__construct.
     */
    public function getInnerIterator(): ?Iterator {}

    /**
     * Rewind to the first element
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Checks if the iterator is valid
     * @return bool true if the iterator is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Get the key of the current element
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Get the current value
     * @return mixed The value of the current element.
     */
    public function current(): mixed {}

    /**
     * Forward to the next element
     * @return void No value is returned.
     */
    public function next(): void {}
}
