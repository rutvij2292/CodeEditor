<?php

/**
 * This object supports cached iteration over another iterator.
 */
class CachingIterator extends IteratorIterator implements ArrayAccess, Countable, Stringable
{
    /**
     * String conversion flag (mutually exclusive): Uses the current element for the iterator's string conversion.
     * This converts the current element to a string only once, regardless of whether it is needed or not.
     */
    public const CALL_TOSTRING = 1;

    /**
     * String conversion flag (mutually exclusive). Uses the current key for the iterator's string conversion.
     */
    public const TOSTRING_USE_KEY = 2;

    /**
     * String conversion flag (mutually exclusive). Uses the current element for the iterator's string conversion.
     * This converts the current element to a string only when (and every time) it is needed.
     */
    public const TOSTRING_USE_CURRENT = 4;

    /**
     * String conversion flag (mutually exclusive). Forwards the string conversion to the inner iterator.
     * This converts the inner iterator to a string only once, regardless of whether it is needed or not.
     */
    public const TOSTRING_USE_INNER = 8;

    /**
     * Ignore exceptions thrown in accessing children. Only used with RecursiveCachingIterator.
     */
    public const CATCH_GET_CHILD = 16;

    /**
     * Cache all read data. This is needed to use CachingIterator::getCache, and ArrayAccess and Countable methods.
     */
    public const FULL_CACHE = 256;

    /**
     * Constructs a new CachingIterator.
     * @param Iterator $iterator The iterator to cache.
     * @param int $flags [optional] A bitmask of flags. See CachingIterator class constants for details.
     */
    public function __construct(Iterator $iterator, int $flags = self::CALL_TOSTRING) {}

    /**
     * Rewind the iterator
     * @return void
     */
    public function rewind(): void {}

    /**
     * Check whether the current element is valid
     * @return bool true on success or false on failure.
     */
    public function valid(): bool {}

    /**
     * Return the key for the current element
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Return the current element
     * @return mixed
     */
    public function current(): mixed {}

    /**
     * Move the iterator forward
     * @return void
     */
    public function next(): void {}

    /**
     * Check whether the inner iterator has a valid next element
     * @return bool true on success or false on failure.
     */
    public function hasNext(): bool {}

    /**
     * Return the string representation of the current iteration based on the flag being used.
     * @return string The string representation of the current iteration based on the flag being used.
     */
    public function __toString(): string {}

    /**
     * Returns the inner iterator
     * @return Iterator an object implementing the Iterator interface.
     */
    public function getInnerIterator(): ?Iterator {}

    /**
     * Get flags used
     * @return int Bitmask of the flags
     */
    public function getFlags(): int {}

    /**
     * The setFlags purpose
     * @param int $flags Bitmask of the flags to set.
     * @return void
     */
    public function setFlags(int $flags): void {}

    /**
     * Internal cache array index to retrieve.
     * @param string $key The index of the element to retrieve.
     * @return mixed
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     */
    public function offsetGet($key): mixed {}

    /**
     * Set an element on the internal cache array.
     * @param string $key The index of the element to be set.
     * @param string $value The new value for the index.
     * @return void
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     */
    public function offsetSet($key, mixed $value): void {}

    /**
     * Remove an element from the internal cache array.
     * @param string $key The index of the element to be unset.
     * @return void
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     */
    public function offsetUnset($key): void {}

    /**
     * Return whether an element at the index exists on the internal cache array.
     * @param string $key The index being checked.
     * @return bool true if an entry referenced by the offset exists, false otherwise.
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     */
    public function offsetExists($key): bool {}

    /**
     * Retrieve the contents of the cache
     * @return array An array containing the cache items.
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     */
    public function getCache(): array {}

    /**
     * The number of elements in the iterator
     * @return int The count of the elements iterated over.
     * @throws BadMethodCallException when the CachingIterator::FULL_CACHE flag is not being used.
     * @since 5.2
     */
    public function count(): int {}
}
