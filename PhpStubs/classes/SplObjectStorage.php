<?php

/**
 * The SplObjectStorage class provides a map from objects to data or, by ignoring data, an object
 * set. This dual purpose can be useful in many cases involving the need to uniquely identify
 * objects.
 * @template TObject of object
 * @template TValue The SplObjectStorage class provides a map from objects to data or, by ignoring data, an object set. This dual purpose can be useful in many cases involving the need to uniquely identify objects.
 * @template-implements Iterator<int, TObject>
 * @template-implements ArrayAccess<TObject, TValue>
 */
class SplObjectStorage implements Countable, SeekableIterator, Serializable, ArrayAccess
{
    /**
     * Adds an object in the storage
     * @param TObject $object The object to add.
     * @param TValue $info [optional] The data to associate with the object.
     * @return void No value is returned.
     */
    public function attach(
        object $object,
        mixed $info = null
    ): void {}

    /**
     * Removes an object from the storage
     * @param TObject $object The object to remove.
     * @return void No value is returned.
     */
    public function detach(object $object): void {}

    /**
     * Checks if the storage contains a specific object
     * @param TObject $object The object to look for.
     * @return bool true if the object is in the storage, false otherwise.
     */
    public function contains(object $object): bool {}

    /**
     * Adds all objects from another storage
     * @param SplObjectStorage<TObject, TValue> $storage The storage you want to import.
     * @return int The number of objects in the storage.
     */
    public function addAll(SplObjectStorage $storage): int {}

    /**
     * Removes objects contained in another storage from the current storage
     * @param SplObjectStorage<TObject, TValue> $storage The storage containing the elements to remove.
     * @return int Returns the number of remaining objects.
     */
    public function removeAll(SplObjectStorage $storage): int {}

    /**
     * Removes all objects except for those contained in another storage from the current storage
     * @param SplObjectStorage<TObject, TValue> $storage The storage containing the elements to retain in the current storage.
     * @return int Returns the number of remaining objects.
     * @since 5.3
     */
    public function removeAllExcept(SplObjectStorage $storage): int {}

    /**
     * Returns the data associated with the current iterator entry
     * @return TValue The data associated with the current iterator position.
     */
    public function getInfo(): mixed {}

    /**
     * Sets the data associated with the current iterator entry
     * @param TValue $info The data to associate with the current iterator entry.
     * @return void No value is returned.
     */
    public function setInfo(mixed $info): void {}

    /**
     * Returns the number of objects in the storage
     * @param int $mode [optional]
     * @return int The number of objects in the storage.
     */
    public function count(int $mode = COUNT_NORMAL): int {}

    /**
     * Rewind the iterator to the first storage element
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Returns if the current iterator entry is valid
     * @return bool true if the iterator entry is valid, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Returns the index at which the iterator currently is
     * @return int The index corresponding to the position of the iterator.
     */
    public function key(): int {}

    /**
     * Returns the current storage entry
     * @return TObject The object at the current iterator position.
     */
    public function current(): object {}

    /**
     * Move to the next entry
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Unserializes a storage from its string representation
     * @param string $data The serialized representation of a storage.
     * @return void No value is returned.
     * @since 5.2
     */
    public function unserialize(string $data): void {}

    /**
     * Serializes the storage
     * @return string A string representing the storage.
     * @since 5.2
     */
    public function serialize(): string {}

    /**
     * Checks whether an object exists in the storage
     * @param TObject $object The object to look for.
     * @return bool true if the object exists in the storage, and false otherwise.
     */
    public function offsetExists($object): bool {}

    /**
     * Associates data to an object in the storage
     * @param TObject $object The object to associate data with.
     * @param TValue $info [optional] The data to associate with the object.
     * @return void No value is returned.
     */
    public function offsetSet(
        mixed $object,
        mixed $info = null
    ): void {}

    /**
     * Removes an object from the storage
     * @param TObject $object The object to remove.
     * @return void No value is returned.
     */
    public function offsetUnset($object): void {}

    /**
     * Returns the data associated with an object
     * @param TObject $object The object to look for.
     * @return TValue The data previously associated with the object in the storage.
     * @throws \UnexpectedValueException Throws UnexpectedValueException when object could not be found.
     */
    public function offsetGet($object): mixed {}

    /**
     * Calculate a unique identifier for the contained objects
     * @param TObject $object object whose identifier is to be calculated.
     * @return string A string with the calculated identifier.
     * @since 5.4
     * @throws \RuntimeException A RuntimeException is thrown when the returned value is not a string.
     */
    public function getHash(object $object): string {}

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
     * @return array
     * @since 7.4
     */
    public function __debugInfo(): array {}

    /**
     * Seeks iterator to a position
     *
     * Seeks to a given position in the iterator.
     * @since 8.4
     * @throws \OutOfBoundsException Throws an OutOfBoundsException if the offset is not seekable.
     */
    public function seek(int $offset): void {}
}
