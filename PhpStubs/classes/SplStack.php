<?php

/**
 * The SplStack class provides the main functionalities of a stack implemented using a doubly linked
 * list by setting the iterator mode to SplDoublyLinkedList::IT_MODE_LIFO.
 * @template TValue The SplStack class provides the main functionalities of a stack implemented using a doubly linked list.
 * @template-extends SplDoublyLinkedList<TValue>
 */
class SplStack extends SplDoublyLinkedList
{
    /**
     * Sets the mode of iteration
     * @param int $mode There are two orthogonal sets of modes that can be set: The direction of the iteration (either one or the other): SplDoublyLinkedList::IT_MODE_LIFO (Stack style)
     * @return int
     */
    public function setIteratorMode(int $mode): int {}
}
