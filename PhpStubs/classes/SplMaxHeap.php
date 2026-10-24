<?php

/**
 * The SplMaxHeap class provides the main functionalities of a heap, keeping the maximum on the top.
 * @template TValue The SplMaxHeap class provides the main functionalities of a heap, keeping the maximum on the top.
 * @template-extends SplHeap<TValue>
 */
class SplMaxHeap extends SplHeap
{
    /**
     * Compare elements in order to place them correctly in the heap while sifting up.
     * @param TValue $value1 The value of the first node being compared.
     * @param TValue $value2 The value of the second node being compared.
     * @return int Result of the comparison, positive integer if value1 is greater than value2, 0 if they are equal, negative integer otherwise. Having multiple elements with the same value in a Heap is not recommended. They will end up in an arbitrary relative position.
     */
    protected function compare(
        mixed $value1,
        mixed $value2
    ): int {}
}
