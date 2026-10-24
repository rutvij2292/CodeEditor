<?php

/**
 * The SplPriorityQueue class provides the main functionalities of a prioritized queue, implemented
 * using a max heap.
 * @template TPriority
 * @template TValue The SplPriorityQueue class provides the main functionalities of an prioritized queue, implemented using a heap.
 * @template-implements Iterator<int, TValue>
 */
class SplPriorityQueue implements Iterator, Countable
{
    public const EXTR_BOTH = 3;

    public const EXTR_PRIORITY = 2;

    public const EXTR_DATA = 1;

    /**
     * Compare priorities in order to place elements correctly in the heap while sifting up.
     * @param TPriority $priority1 The priority of the first node being compared.
     * @param TPriority $priority2 The priority of the second node being compared.
     * @return int Result of the comparison, positive integer if priority1 is greater than priority2, 0 if they are equal, negative integer otherwise. Multiple elements with the same priority will get dequeued in no particular order.
     */
    public function compare(
        mixed $priority1,
        mixed $priority2
    ): int {}

    /**
     * Inserts an element in the queue by sifting it up.
     * @param TValue $value The value to insert.
     * @param TPriority $priority The associated priority.
     * @return true Always returns true.
     */
    public function insert(
        mixed $value,
        mixed $priority
    ): true {}

    /**
     * Sets the mode of extraction
     * @param int $flags Defines what is extracted by SplPriorityQueue::current, SplPriorityQueue::top and SplPriorityQueue::extract. SplPriorityQueue::EXTR_DATA (0x00000001): Extract the data
     * @return int Returns the flags of extraction.
     */
    public function setExtractFlags(int $flags): int {}

    /**
     * Peeks at the node from the top of the queue
     * @return TValue The value or priority (or both) of the top node, depending on the extract flag.
     */
    public function top(): mixed {}

    /**
     * Extracts a node from top of the heap and sift up.
     * @return TValue The value or priority (or both) of the extracted node, depending on the extract flag.
     */
    public function extract(): mixed {}

    /**
     * Counts the number of elements in the queue.
     * @return int the number of elements in the queue.
     */
    public function count(): int {}

    /**
     * Checks whether the queue is empty.
     * @return bool whether the queue is empty.
     */
    public function isEmpty(): bool {}

    /**
     * Rewind iterator back to the start (no-op)
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Return current node pointed by the iterator
     * @return TValue The value or priority (or both) of the current node, depending on the extract flag.
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
     * Check whether the queue contains more nodes
     * @return bool true if the queue contains any more nodes, false otherwise.
     */
    public function valid(): bool {}

    /**
     * Recover from the corrupted state and allow further actions on the queue.
     */
    public function recoverFromCorruption(): true {}

    /**
     * Tells if the priority queue is in a corrupted state
     * @return bool Returns true if the priority queue is corrupted, false otherwise.
     * @since 7.0
     */
    public function isCorrupted(): bool {}

    /**
     * Get the flags of extraction
     * @return int
     * @since 7.0
     */
    public function getExtractFlags(): int {}

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
