<?php

/**
 * Weak maps allow creating a map from objects to arbitrary values
 * (similar to SplObjectStorage) without preventing the objects that are used
 * as keys from being garbage collected. If an object key is garbage collected,
 * it will simply be removed from the map.
 * @since 8.0
 * @template TKey of object
 * @template TValue
 * @template-implements IteratorAggregate<TKey, TValue>
 * @template-implements ArrayAccess<TKey, TValue>
 */
final class WeakMap implements ArrayAccess, Countable, IteratorAggregate
{
    /**
     * Returns true if the value for the object is contained in
     * the WeakMap and false instead.
     * @param TKey $object Any object
     * @return bool Returns true if the object is contained in the map, false otherwise.
     */
    public function offsetExists($object): bool {}

    /**
     * Returns the existsing value by an object.
     * @param TKey $object Any object
     * @return TValue Value associated with the key object
     * @throws \Error Throws an Error on failure.
     */
    public function offsetGet($object): mixed {}

    /**
     * Sets a new value for an object.
     * @param TKey $object Any object
     * @param TValue $value Any value
     * @return void No value is returned.
     */
    public function offsetSet($object, mixed $value): void {}

    /**
     * Force removes an object value from the WeakMap instance.
     * @param TKey $object Any object
     * @return void No value is returned.
     */
    public function offsetUnset($object): void {}

    /**
     * Returns an iterator in the "[object => mixed]" format.
     * @return Iterator<TKey, TValue> An instance of an object implementing Iterator or Traversable
     * @throws \Exception Throws an Exception on failure.
     */
    public function getIterator(): Iterator {}

    /**
     * Returns the number of items in the WeakMap instance.
     * @return int<0,max> Returns the number of live entries in the map.
     */
    public function count(): int {}
}
