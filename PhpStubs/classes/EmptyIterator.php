<?php

/**
 * The EmptyIterator class for an empty iterator.
 */
class EmptyIterator implements Iterator
{
    /**
     * Return the current element
     * @return mixed Can return any type.
     * @throws \Exception Throws an Exception if called.
     */
    public function current(): never {}

    /**
     * Move forward to next element
     * @return void Any returned value is ignored.
     */
    public function next(): void {}

    /**
     * Return the key of the current element
     * @return mixed The key of the current element.
     * @throws \Exception Throws an Exception if called.
     */
    public function key(): never {}

    /**
     * Checks if current position is valid
     * @return bool The return value will be casted to boolean and then evaluated. Returns true on success or false on failure.
     */
    public function valid(): false {}

    /**
     * Rewind the Iterator to the first element
     * @return void Any returned value is ignored.
     */
    public function rewind(): void {}
}
