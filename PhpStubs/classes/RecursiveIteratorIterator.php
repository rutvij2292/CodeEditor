<?php

/**
 * Can be used to iterate through recursive iterators.
 */
class RecursiveIteratorIterator implements OuterIterator
{
    /**
     * The default. Lists only leaves in iteration.
     */
    public const LEAVES_ONLY = 0;

    /**
     * Lists leaves and parents in iteration with parents coming first.
     */
    public const SELF_FIRST = 1;

    /**
     * Lists leaves and parents in iteration with leaves coming first.
     */
    public const CHILD_FIRST = 2;

    /**
     * Special flag: Ignore exceptions thrown in accessing children.
     */
    public const CATCH_GET_CHILD = 16;

    /**
     * Construct a RecursiveIteratorIterator
     * @param Traversable $iterator The iterator being constructed from. Either a RecursiveIterator or IteratorAggregate.
     * @param int $mode [optional] The operation mode. See class constants for details.
     * @param int $flags [optional] A bitmask of special flags. See class constants for details.
     * @since 5.1
     */
    public function __construct(
        Traversable $iterator,
        int $mode = self::LEAVES_ONLY,
        int $flags = 0
    ) {}

    /**
     * Rewind the iterator to the first element of the top level inner iterator
     * @return void
     */
    public function rewind(): void {}

    /**
     * Check whether the current position is valid
     * @return bool true if the current position is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Access the current key
     * @return mixed The key of the current element.
     */
    public function key(): mixed {}

    /**
     * Access the current element value
     * @return mixed The current elements value.
     */
    public function current(): mixed {}

    /**
     * Move forward to the next element
     * @return void
     */
    public function next(): void {}

    /**
     * Get the current depth of the recursive iteration
     * @return int The current depth of the recursive iteration.
     */
    public function getDepth(): int {}

    /**
     * The current active sub iterator
     * @param int $level [optional]
     * @return RecursiveIterator|null The current active sub iterator.
     */
    public function getSubIterator(int|null $level = null): ?RecursiveIterator {}

    /**
     * Get inner iterator
     * @return RecursiveIterator The current active sub iterator.
     */
    public function getInnerIterator(): RecursiveIterator {}

    /**
     * Begin Iteration
     * @return void
     */
    public function beginIteration(): void {}

    /**
     * End Iteration
     * @return void
     */
    public function endIteration(): void {}

    /**
     * Has children
     * @return bool true if the element has children, otherwise false
     */
    public function callHasChildren(): bool {}

    /**
     * Get children
     * @return RecursiveIterator|null A RecursiveIterator.
     */
    public function callGetChildren(): ?RecursiveIterator {}

    /**
     * Begin children
     * @return void
     */
    public function beginChildren(): void {}

    /**
     * End children
     * @return void
     */
    public function endChildren(): void {}

    /**
     * Next element
     * @return void
     */
    public function nextElement(): void {}

    /**
     * Set max depth
     * @param int $maxDepth [optional] The maximum allowed depth. Default -1 is used for any depth.
     * @return void
     * @throws \Exception Emits an Exception if maxDepth is less than -1.
     */
    public function setMaxDepth(int $maxDepth = -1): void {}

    /**
     * Get max depth
     * @return int|false The maximum accepted depth, or false if any depth is allowed.
     */
    public function getMaxDepth(): int|false {}
}
