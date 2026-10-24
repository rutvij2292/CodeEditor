<?php

/**
 * The SplMinHeap class provides the main functionalities of a heap, keeping the minimum on the top.
 * @template TValue The SplMinHeap class provides the main functionalities of a heap, keeping the minimum on the top.
 * @template-extends SplHeap<TValue>
 */
class SplMinHeap extends SplHeap
{
    /**
     * Compare elements in order to place them correctly in the heap while sifting up.
     * @param TValue $value1 The value of the first node being compared.
     * @param TValue $value2 The value of the second node being compared.
     * @return int Result of the comparison, positive integer if value1 is lower than value2, 0 if they are equal, negative integer otherwise. Having multiple elements with the same value in a Heap is not recommended. They will end up in an arbitrary relative position.
     */
    protected function compare(
        mixed $value1,
        mixed $value2
    ): int {}

    /**
     * Extracts a node from top of the heap and sift up.
     * @return TValue The value of the extracted node.
     */
    public function extract(): mixed {}

    /**
     * Inserts an element in the heap by sifting it up.
     * @param TValue $value The value to insert.
     * @return true
     */
    public function insert(mixed $value): bool {}

    /**
     * Peeks at the node from the top of the heap
     * @return TValue The value of the node on the top.
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
     * @return void
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
     * @return void
     */
    public function next(): void {}

    /**
     * Check whether the heap contains more nodes
     * @return bool true if the heap contains any more nodes, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Recover from the corrupted state and allow further actions on the heap.
     * @return bool
     */
    public function recoverFromCorruption(): bool {}
}
