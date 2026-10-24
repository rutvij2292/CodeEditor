<?php

/**
 * This class allows objects to work as arrays.
 * @template TKey
 * @template TValue
 * @template-implements IteratorAggregate<TKey, TValue>
 * @template-implements ArrayAccess<TKey, TValue>
 */
class ArrayObject implements IteratorAggregate, ArrayAccess, Serializable, Countable
{
    /**
     * Properties of the object have their normal functionality when accessed as list (var_dump, foreach, etc.).
     */
    public const STD_PROP_LIST = 1;

    /**
     * Entries can be accessed as properties (read and write).
     */
    public const ARRAY_AS_PROPS = 2;

    /**
     * Construct a new array object
     * @param array<TValue>|object $array The input parameter accepts an array or an Object.
     * @param int $flags Flags to control the behaviour of the ArrayObject object.
     * @param class-string<ArrayIterator> $iteratorClass Specify the class that will be used for iteration of the ArrayObject object. ArrayIterator is the default class used.
     */
    public function __construct(
        object|array $array = [],
        int $flags = 0,
        string $iteratorClass = "ArrayIterator"
    ) {}

    /**
     * Returns whether the requested index exists
     * @param TKey $key The index being checked.
     * @return bool true if the requested index exists, otherwise false
     */
    public function offsetExists(mixed $key): bool {}

    /**
     * Returns the value at the specified index
     * @param TKey $key The index with the value.
     * @return TValue|null The value at the specified index or null.
     */
    public function offsetGet(mixed $key): mixed {}

    /**
     * Sets the value at the specified index to newval
     * @param TKey $key The index being set.
     * @param TValue $value The new value for the index.
     * @return void No value is returned.
     */
    public function offsetSet(
        mixed $key,
        mixed $value
    ): void {}

    /**
     * Unsets the value at the specified index
     * @param TKey $key The index being unset.
     * @return void No value is returned.
     */
    public function offsetUnset(mixed $key): void {}

    /**
     * Appends the value
     * @param TValue $value The value being appended.
     * @return void No value is returned.
     */
    public function append(mixed $value): void {}

    /**
     * Creates a copy of the ArrayObject.
     * @return array<TValue> a copy of the array. When the ArrayObject refers to an object an array of the public properties of that object will be returned.
     */
    public function getArrayCopy(): array {}

    /**
     * Get the number of public properties in the ArrayObject
     * When the ArrayObject is constructed from an array all properties are public.
     * @return int The number of public properties in the ArrayObject.
     */
    public function count(): int {}

    /**
     * Gets the behavior flags.
     * @return int the behavior flags of the ArrayObject.
     */
    public function getFlags(): int {}

    /**
     * Sets the behavior flags.
     * @param int $flags The new ArrayObject behavior. It takes on either a bitmask, or named constants. Using named constants is strongly encouraged to ensure compatibility for future versions. The available behavior flags are listed below. The actual meanings of these flags are described in the ...
     * @return void No value is returned.
     */
    public function setFlags(int $flags): void {}

    /**
     * Sort the entries by value
     */
    public function asort(int $flags = SORT_REGULAR): true {}

    /**
     * Sort the entries by key
     */
    public function ksort(int $flags = SORT_REGULAR): true {}

    /**
     * Sort the entries with a user-defined comparison function and maintain key association
     * @param callable(TValue, TValue):int $callback Function cmp_function should accept two parameters which will be filled by pairs of entries. The comparison function must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal ...
     */
    public function uasort(callable $callback): true {}

    /**
     * Sort the entries by keys using a user-defined comparison function
     * @param callable(TValue, TValue):int $callback The callback comparison function. Function cmp_function should accept two parameters which will be filled by pairs of entry keys. The comparison function must return an integer less than, equal to, or greater than zero if the first argument is ...
     */
    public function uksort(callable $callback): true {}

    /**
     * Sort entries using a "natural order" algorithm
     */
    public function natsort(): true {}

    /**
     * Sort an array using a case insensitive "natural order" algorithm
     */
    public function natcasesort(): true {}

    /**
     * Unserialize an ArrayObject
     * @param string $data The serialized ArrayObject.
     * @return void
     */
    public function unserialize(string $data): void {}

    /**
     * Serialize an ArrayObject
     * @return string The serialized representation of the ArrayObject.
     */
    public function serialize(): string {}

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

    /**
     * Create a new iterator from an ArrayObject instance
     * @return ArrayIterator<TKey, TValue> An iterator from an ArrayObject.
     */
    public function getIterator(): Iterator {}

    /**
     * Exchange the array for another one.
     * @param mixed $array The new array or object to exchange with the current array.
     * @return array the old array.
     */
    public function exchangeArray(object|array $array): array {}

    /**
     * Sets the iterator classname for the ArrayObject.
     * @param class-string<ArrayIterator> $iteratorClass The classname of the array iterator to use when iterating over this object.
     * @return void No value is returned.
     */
    public function setIteratorClass(string $iteratorClass): void {}

    /**
     * Gets the iterator classname for the ArrayObject.
     * @return class-string<ArrayIterator> the iterator class name that is used to iterate over this object.
     */
    public function getIteratorClass(): string {}
}
