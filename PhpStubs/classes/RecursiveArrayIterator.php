<?php

/**
 * This iterator allows to unset and modify values and keys while iterating over Arrays and Objects
 * in the same way as the ArrayIterator. Additionally it is possible to iterate
 * over the current iterator entry.
 */
class RecursiveArrayIterator extends ArrayIterator implements RecursiveIterator
{
    public const CHILD_ARRAYS_ONLY = 4;

    /**
     * Returns whether current entry is an array or an object.
     * @return bool true if the current entry is an array or an object, otherwise false is returned.
     */
    public function hasChildren(): bool {}

    /**
     * Returns an iterator for the current entry if it is an array or an object.
     * @return RecursiveArrayIterator|null An iterator for the current entry, if it is an array or object.
     * @throws \InvalidArgumentException An InvalidArgumentException will be thrown if the current entry does not contain an array or an object.
     */
    public function getChildren(): ?RecursiveArrayIterator {}

    /**
     * Return current array key
     * @return string|int|null The key of the current element.
     */
    public function key(): string|int|null {}
}
