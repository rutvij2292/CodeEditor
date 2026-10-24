<?php

/**
 * The SplQueue class provides the main functionalities of a queue implemented using a doubly linked
 * list by setting the iterator mode to SplDoublyLinkedList::IT_MODE_FIFO.
 * @template TValue The SplQueue class provides the main functionalities of a queue implemented using a doubly linked list.
 * @template-extends SplDoublyLinkedList<TValue>
 */
class SplQueue extends SplDoublyLinkedList
{
    /**
     * Adds an element to the queue.
     * @param TValue $value The value to enqueue.
     * @return void No value is returned.
     */
    public function enqueue(mixed $value): void {}

    /**
     * Dequeues a node from the queue
     * @return TValue The value of the dequeued node.
     */
    public function dequeue(): mixed {}

    /**
     * Sets the mode of iteration
     * @param int $mode There are two orthogonal sets of modes that can be set: The direction of the iteration (either one or the other): SplDoublyLinkedList::IT_MODE_LIFO (Stack style)
     * @return int
     */
    public function setIteratorMode(int $mode): int {}
}
