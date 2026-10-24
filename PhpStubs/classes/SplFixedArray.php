<?php

/**
 * The SplFixedArray class provides the main functionalities of array. The main difference between a
 * SplFixedArray and a normal PHP array is that the SplFixedArray must be resized manually and
 * allows only integers within the range as indexes. The advantage is that it uses less memory than
 * a standard array.
 * @template TValue The SplFixedArray class provides the main functionalities of array. The main differences between a SplFixedArray and a normal PHP array is that the SplFixedArray is of fixed length and allows only integers within the range as indexes. The advantage is that it allows a faster array ...
 * @template-implements Iterator<int, TValue>
 * @template-implements ArrayAccess<int, TValue>
 * @template-implements IteratorAggregate<int, TValue>
 */
class SplFixedArray implements Iterator, ArrayAccess, Countable, IteratorAggregate, JsonSerializable
{
    /**
     * Constructs a new fixed array
     * @param int $size [optional]
     * @throws \ValueError Throws a ValueError when size is a negative integer.
     */
    public function __construct(int $size = 0) {}

    /**
     * Returns the size of the array
     * @return int the size of the array.
     */
    public function count(): int {}

    /**
     * Returns a PHP array from the fixed array
     * @return TValue[] a PHP array, similar to the fixed array.
     */
    public function toArray(): array {}

    /**
     * Import a PHP array in a SplFixedArray instance
     * @param array $array The array to import.
     * @param bool $preserveKeys [optional] Try to save the numeric indexes used in the original array.
     * @return SplFixedArray an instance of SplFixedArray containing the array content.
     */
    public static function fromArray(
        array $array,
        bool $preserveKeys = true
    ): SplFixedArray {}

    /**
     * Gets the size of the array
     * @return int the size of the array, as an integer.
     */
    public function getSize(): int {}

    /**
     * Change the size of an array
     * @param int $size The new array size.
     * @return bool Always returns true.
     * @throws \ValueError Throws ValueError when size is less than zero.
     */
    public function setSize(int $size): bool {}

    /**
     * Returns whether the requested index exists
     * @param int $index The index being checked.
     * @return bool true if the requested index exists, otherwise false
     */
    public function offsetExists($index): bool {}

    /**
     * Returns the value at the specified index
     * @param int $index The index with the value.
     * @return TValue The value at the specified index.
     * @throws \RuntimeException Throws RuntimeException when index is outside the defined size of the array or when index cannot be parsed as an integer.
     */
    public function offsetGet($index): mixed {}

    /**
     * Sets a new value at a specified index
     * @param int $index The index being set.
     * @param TValue $value The new value for the index.
     * @return void No value is returned.
     * @throws \RuntimeException Throws RuntimeException when index is outside the defined size of the array or when index cannot be parsed as an integer.
     */
    public function offsetSet($index, mixed $value): void {}

    /**
     * Unsets the value at the specified $index
     * @param int $index The index being unset.
     * @return void No value is returned.
     * @throws \RuntimeException Throws RuntimeException when index is outside the defined size of the array or when index cannot be parsed as an integer.
     */
    public function offsetUnset($index): void {}

    /**
     * Rewind iterator back to the start
     * @return void No value is returned.
     * @removed 8.0
     */
    public function rewind() {}

    /**
     * Return current array entry
     * @return TValue The current element value.
     * @removed 8.0
     * @throws \RuntimeException Throws RuntimeException when the internal array pointer points to an invalid index or is out of bounds.
     */
    public function current() {}

    /**
     * Return current array index
     * @return int The current array index.
     * @removed 8.0
     */
    public function key() {}

    /**
     * Move to next entry
     * @return void No value is returned.
     * @removed 8.0
     */
    public function next() {}

    /**
     * Check whether the array contains more elements
     * @return bool true if the array contains any more elements, false otherwise.
     * @removed 8.0
     */
    public function valid(): bool {}

    /**
     * Reinitialises the array after being unserialised
     * @return void No value is returned.
     */
    public function __wakeup(): void {}

    /**
     * Serializes the SplFixedArray object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into an SplFixedArray object
     * @param array $data The value being deserialized.
     * @return void No value is returned.
     */
    public function __unserialize(array $data): void {}

    /**
     * Retrieve the iterator to go through the array
     *
     * Returns the iterator to go through the array.
     * @since 8.0
     * @return Iterator<int, TValue> An instance of an object implementing Iterator to go through the array.
     */
    public function getIterator(): Iterator {}

    /**
     * Returns a representation that can be converted to JSON
     *
     * Serializes the array to a value that can be serialized natively by json_encode.
     * @return array Returns array data which can be serialized by json_encode, which is a value of any type other than a resource.
     */
    public function jsonSerialize(): array {}
}
