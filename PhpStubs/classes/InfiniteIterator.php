<?php

/**
 * The InfiniteIterator allows one to
 * infinitely iterate over an iterator without having to manually
 * rewind the iterator upon reaching its end.
 */
class InfiniteIterator extends IteratorIterator
{
    /**
     * Constructs an InfiniteIterator
     * @param Iterator $iterator The iterator to infinitely iterate over.
     */
    public function __construct(Iterator $iterator) {}

    /**
     * Moves the inner Iterator forward or rewinds it
     * @return void No value is returned.
     */
    public function next(): void {}
}
