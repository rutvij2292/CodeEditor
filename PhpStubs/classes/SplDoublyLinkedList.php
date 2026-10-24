<?php

/**
 * The SplDoublyLinkedList class provides the main functionalities of a doubly linked list.
 * @template TValue The SplDoublyLinkedList class provides the main functionalities of a doubly linked list.
 * @template-implements Iterator<int, TValue>
 * @template-implements ArrayAccess<int, TValue>
 */
class SplDoublyLinkedList implements Iterator, Countable, ArrayAccess, Serializable
{
    public const IT_MODE_LIFO = 2;

    public const IT_MODE_FIFO = 0;

    public const IT_MODE_DELETE = 1;

    public const IT_MODE_KEEP = 0;

    /**
     * Add/insert a new value at the specified index
     * @param mixed $index The index where the new value is to be inserted.
     * @param TValue $value The new value for the index.
     * @return void No value is returned.
     * @since 5.5
     * @throws \OutOfRangeException Throws OutOfRangeException when index is out of bounds or when index cannot be parsed as an integer.
     */
    public function add(
        int $index,
        mixed $value
    ): void {}

    /**
     * Pops a node from the end of the doubly linked list
     * @return TValue The value of the popped node.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function pop(): mixed {}

    /**
     * Shifts a node from the beginning of the doubly linked list
     * @return TValue The value of the shifted node.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function shift(): mixed {}

    /**
     * Pushes an element at the end of the doubly linked list
     * @param TValue $value The value to push.
     * @return void No value is returned.
     */
    public function push(mixed $value): void {}

    /**
     * Prepends the doubly linked list with an element
     * @param TValue $value The value to unshift.
     * @return void No value is returned.
     */
    public function unshift(mixed $value): void {}

    /**
     * Peeks at the node from the end of the doubly linked list
     * @return TValue The value of the last node.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function top(): mixed {}

    /**
     * Peeks at the node from the beginning of the doubly linked list
     * @return TValue The value of the first node.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function bottom(): mixed {}

    /**
     * Counts the number of elements in the doubly linked list.
     * @return int the number of elements in the doubly linked list.
     */
    public function count(): int {}

    /**
     * Checks whether the doubly linked list is empty.
     * @return bool whether the doubly linked list is empty.
     */
    public function isEmpty(): bool {}

    /**
     * Sets the mode of iteration
     * @param int $mode There are two orthogonal sets of modes that can be set: The direction of the iteration (either one or the other): SplDoublyLinkedList::IT_MODE_LIFO (Stack style)
     * @return int Returns the different modes and flags that affect the iteration.
     */
    public function setIteratorMode(int $mode): int {}

    /**
     * Returns the mode of iteration
     * @return int the different modes and flags that affect the iteration.
     */
    public function getIteratorMode(): int {}

    /**
     * Returns whether the requested $index exists
     * @param mixed $index The index being checked.
     * @return bool true if the requested index exists, otherwise false
     */
    public function offsetExists($index): bool {}

    /**
     * Returns the value at the specified $index
     * @param mixed $index The index with the value.
     * @return TValue The value at the specified index.
     * @throws \OutOfRangeException Throws OutOfRangeException when index is out of bounds or when index cannot be parsed as an integer.
     */
    public function offsetGet($index): mixed {}

    /**
     * Sets the value at the specified $index to $newval
     * @param mixed $index The index being set.
     * @param TValue $value The new value for the index.
     * @return void No value is returned.
     * @throws \OutOfRangeException Throws OutOfRangeException when index is out of bounds or when index cannot be parsed as an integer.
     */
    public function offsetSet($index, mixed $value): void {}

    /**
     * Unsets the value at the specified $index
     * @param mixed $index The index being unset.
     * @return void No value is returned.
     * @throws \OutOfRangeException Throws OutOfRangeException when index is out of bounds or when index cannot be parsed as an integer.
     */
    public function offsetUnset($index): void {}

    /**
     * Rewind iterator back to the start
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Return current array entry
     * @return TValue The current node value.
     */
    public function current(): mixed {}

    /**
     * Return current node index
     * @return int The current node index.
     */
    public function key(): int {}

    /**
     * Move to next entry
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Move to previous entry
     * @return void No value is returned.
     */
    public function prev(): void {}

    /**
     * Check whether the doubly linked list contains more nodes
     * @return bool true if the doubly linked list contains any more nodes, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Unserializes the storage
     * @param string $data The serialized string.
     * @return void
     * @since 5.4
     */
    public function unserialize(string $data): void {}

    /**
     * Serializes the storage
     * @return string The serialized string.
     * @since 5.4
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
}
