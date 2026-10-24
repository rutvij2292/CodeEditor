<?php

/**
 * An Iterator that sequentially iterates over all attached iterators
 */
class MultipleIterator implements Iterator
{
    public const MIT_NEED_ANY = 0;

    public const MIT_NEED_ALL = 1;

    public const MIT_KEYS_NUMERIC = 0;

    public const MIT_KEYS_ASSOC = 2;

    /**
     * Constructs a new MultipleIterator
     * @param int $flags Defaults to MultipleIterator::MIT_NEED_ALL | MultipleIterator::MIT_KEYS_NUMERIC
     */
    public function __construct(
        int $flags = MultipleIterator::MIT_NEED_ALL|MultipleIterator::MIT_KEYS_NUMERIC
    ) {}

    /**
     * Gets the flag information
     * @return int Information about the flags, as an integer.
     */
    public function getFlags(): int {}

    /**
     * Sets flags
     * @param int $flags The flags to set, according to the Flag Constants
     * @return void
     */
    public function setFlags(int $flags): void {}

    /**
     * Attaches iterator information
     * @param Iterator $iterator The new iterator to attach.
     * @param int|string|null $info [optional] The associative information for the Iterator, which must be an integer, a string, or null.
     * @return void Description...
     */
    public function attachIterator(Iterator $iterator, int|string|null $info = null): void {}

    /**
     * Detaches an iterator
     * @param Iterator $iterator The iterator to detach.
     * @return void
     */
    public function detachIterator(Iterator $iterator): void {}

    /**
     * Checks if an iterator is attached
     * @param Iterator $iterator The iterator to check.
     * @return bool true on success or false on failure.
     */
    public function containsIterator(Iterator $iterator): bool {}

    /**
     * Gets the number of attached iterator instances
     * @return int The number of attached iterator instances (as an integer).
     */
    public function countIterators(): int {}

    /**
     * Rewinds all attached iterator instances
     * @return void
     */
    public function rewind(): void {}

    /**
     * Checks the validity of sub iterators
     * @return bool true if one or all sub iterators are valid depending on flags, otherwise false
     */
    public function valid(): bool {}

    /**
     * Gets the registered iterator instances
     * @return array An array of all registered iterator instances.
     * @throws \RuntimeException A RuntimeException if the iterator is invalid (as of PHP 8.1.0), or mode MIT_NEED_ALL is set, and at least one attached iterator is not valid. Calling this method from triggers warning "Illegal type returned".
     */
    public function key(): array {}

    /**
     * Gets the registered iterator instances
     * @return array An array containing the current values of each attached iterator.
     * @throws RuntimeException if mode MIT_NEED_ALL is set and at least one attached iterator is not valid.
     * @throws InvalidArgumentException if a key is NULL and MIT_KEYS_ASSOC is set.
     */
    public function current(): array {}

    /**
     * Moves all attached iterator instances forward
     * @return void
     */
    public function next(): void {}

    /**
     * @return array
     * @since 7.4
     */
    public function __debugInfo(): array {}
}
