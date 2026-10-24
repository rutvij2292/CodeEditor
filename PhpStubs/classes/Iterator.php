<?php

/**
 * Interface for external iterators or objects that can be iterated
 * themselves internally.
 * @template TKey
 * @template-covariant TValue
 * @template-extends Traversable<TKey, TValue>
 */
interface Iterator extends Traversable
{
    /**
     * Return the current element
     * @return TValue Can return any type.
     */
    public function current(): mixed;

    /**
     * Move forward to next element
     * @return void Any returned value is ignored.
     */
    public function next(): void;

    /**
     * Return the key of the current element
     * @return TKey|null TKey on success, or null on failure.
     */
    public function key(): mixed;

    /**
     * Checks if current position is valid
     * @return bool The return value will be casted to boolean and then evaluated. Returns true on success or false on failure.
     */
    public function valid(): bool;

    /**
     * Rewind the Iterator to the first element
     * @return void Any returned value is ignored.
     */
    public function rewind(): void;
}
