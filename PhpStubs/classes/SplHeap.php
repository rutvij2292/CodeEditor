<?php

/**
 * The SplHeap class provides the main functionalities of a Heap.
 * @template TValue The SplHeap class provides the main functionalities of an Heap.
 * @template-implements Iterator<int, TValue>
 */
abstract class SplHeap implements Iterator, Countable
{
    /**
     * Extracts a node from top of the heap and sift up.
     * @return TValue The value of the extracted node.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function extract(): mixed {}

    /**
     * Inserts an element in the heap by sifting it up.
     * @param TValue $value The value to insert.
     * @return bool Always returns true.
     */
    public function insert(mixed $value): bool {}

    /**
     * Peeks at the node from the top of the heap
     * @return TValue The value of the node on the top.
     * @throws \RuntimeException Throws RuntimeException when the data-structure is empty.
     */
    public function top(): mixed {}

    /**
     * Counts the number of elements in the heap.
     * @return int the number of elements in the heap.
     */
    public function count(): int {}

    /**
     * Checks whether the heap is empty.
     * @return bool whether the heap is empty.
     */
    public function isEmpty(): bool {}

    /**
     * Rewind iterator back to the start (no-op)
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Return current node pointed by the iterator
     * @return TValue The current node value.
     */
    public function current(): mixed {}

    /**
     * Return current node index
     * @return int The current node index.
     */
    public function key(): int {}

    /**
     * Move to the next node
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Check whether the heap contains more nodes
     * @return bool true if the heap contains any more nodes, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Recover from the corrupted state and allow further actions on the heap.
     * @return bool Always returns true.
     */
    public function recoverFromCorruption(): bool {}

    /**
     * Compare elements in order to place them correctly in the heap while sifting up.
     * @param mixed $value1 The value of the first node being compared.
     * @param mixed $value2 The value of the second node being compared.
     * @return int Result of the comparison, positive integer if value1 is greater than value2, 0 if they are equal, negative integer otherwise. Having multiple elements with the same value in a Heap is not recommended. They will end up in an arbitrary relative position.
     */
    abstract protected function compare(
        mixed $value1,
        mixed $value2
    ): int;

    /**
     * Tells if the heap is in a corrupted state
     * @return bool Returns true if the heap is corrupted, false otherwise.
     * @since 7.0
     */
    public function isCorrupted(): bool {}

    /**
     * @return array
     * @since 7.4
     */
    public function __debugInfo(): array {}

    /**
     * @return array
     * @since 8.5
     */
    public function __serialize(): array {}

    /**
     * @since 8.5
     */
    public function __unserialize(array $data): void {}
}
