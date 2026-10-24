<?php

/**
 * This iterator allows to unset and modify values and keys while iterating
 * over Arrays and Objects.
 * @template TKey of array-key
 * @template TValue
 * @template-implements SeekableIterator<TKey, TValue>
 * @template-implements ArrayAccess<TKey, TValue>
 */
class ArrayIterator implements SeekableIterator, ArrayAccess, Serializable, Countable
{
    public const STD_PROP_LIST = 1;

    public const ARRAY_AS_PROPS = 2;

    /**
     * Construct an ArrayIterator
     * @param array<TKey, TValue>|object $array The array or object to be iterated on.
     * @param int $flags Flags to control the behaviour of the ArrayObject object.
     * @see ArrayObject::setFlags()
     */
    public function __construct(
        object|array $array = [],
        int $flags = 0
    ) {}

    /**
     * Check if offset exists
     * @param TKey $key The offset being checked.
     * @return bool true if the offset exists, otherwise false
     */
    public function offsetExists(mixed $key): bool {}

    /**
     * Get value for an offset
     * @param TKey $key The offset to get the value from.
     * @return TValue|null The value at offset index.
     */
    public function offsetGet(mixed $key): mixed {}

    /**
     * Set value for an offset
     * @param TKey $key The index to set for.
     * @param TValue $value The new value to store at the index.
     * @return void
     */
    public function offsetSet(
        mixed $key,
        mixed $value
    ): void {}

    /**
     * Unset value for an offset
     * @param TKey $key The offset to unset.
     * @return void No value is returned.
     */
    public function offsetUnset(mixed $key): void {}

    /**
     * Append an element
     * @param TValue $value The value to append.
     * @return void
     */
    public function append(mixed $value): void {}

    /**
     * Get array copy
     * @return array<TKey, TValue> A copy of the array, or array of public properties if ArrayIterator refers to an object.
     */
    public function getArrayCopy(): array {}

    /**
     * Count elements
     * @return int<0,max> The number of elements or public properties in the associated array or object, respectively.
     */
    public function count(): int {}

    /**
     * Get flags
     * @return int The current flags.
     */
    public function getFlags(): int {}

    /**
     * Set behaviour flags
     * @param int $flags A bitmask as follows: 0 = Properties of the object have their normal functionality when accessed as list (var_dump, foreach, etc.). 1 = Array indices can be accessed as properties in read/write.
     * @return void No value is returned.
     */
    public function setFlags(int $flags): void {}

    /**
     * Sort array by values
     */
    public function asort(int $flags = SORT_REGULAR): true {}

    /**
     * Sort array by keys
     */
    public function ksort(int $flags = SORT_REGULAR): true {}

    /**
     * User defined sort
     * @param callable(TValue, TValue):int $callback The compare function used for the sort.
     */
    public function uasort(callable $callback): true {}

    /**
     * User defined sort
     * @param callable(TKey, TKey):int $callback The compare function used for the sort.
     */
    public function uksort(callable $callback): true {}

    /**
     * Sort an array naturally
     */
    public function natsort(): true {}

    /**
     * Sort an array naturally, case insensitive
     */
    public function natcasesort(): true {}

    /**
     * Unserialize
     * @param string $data The serialized ArrayIterator object to be unserialized.
     * @return void
     */
    public function unserialize(string $data): void {}

    /**
     * Serialize
     * @return string The serialized ArrayIterator.
     */
    public function serialize(): string {}

    /**
     * Rewind array back to the start
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Return current array entry
     * @return TValue The current array entry.
     */
    public function current(): mixed {}

    /**
     * Return current array key
     * @return TKey|null The key of the current element.
     */
    public function key(): string|int|null {}

    /**
     * Move to next entry
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Check whether array contains more entries
     * @return bool Returns true if the iterator is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Seek to position
     * @param int $offset The position to seek to.
     * @return void No value is returned.
     * @throws \OutOfBoundsException Throws an OutOfBoundsException if the offset is not seekable.
     */
    public function seek(int $offset): void {}

    /**
     * @return array
     * @since 7.4
     */
    public function __debugInfo(): array {}

    /**
     * @return array
     * @since 7.4
     */
    public function __serialize(): array {}

    /**
     * @param array $data
     * @since 7.4
     */
    public function __unserialize(array $data): void {}
}
