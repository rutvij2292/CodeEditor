<?php

/**
 * Allows iterating over a RecursiveIterator to generate an ASCII graphic tree.
 */
class RecursiveTreeIterator extends RecursiveIteratorIterator
{
    public const BYPASS_CURRENT = 4;

    public const BYPASS_KEY = 8;

    public const PREFIX_LEFT = 0;

    public const PREFIX_MID_HAS_NEXT = 1;

    public const PREFIX_MID_LAST = 2;

    public const PREFIX_END_HAS_NEXT = 3;

    public const PREFIX_END_LAST = 4;

    public const PREFIX_RIGHT = 5;

    /**
     * Construct a RecursiveTreeIterator
     * @param RecursiveIterator|IteratorAggregate $iterator The RecursiveIterator or IteratorAggregate to iterate over.
     * @param int $flags [optional] Flags to control the behavior of the RecursiveTreeIterator object.
     * @param int $cachingIteratorFlags [optional] Flags to affect the behavior of the RecursiveCachingIterator used internally.
     * @param int $mode [optional] Flags to affect the behavior of the RecursiveIteratorIterator used internally.
     */
    public function __construct(
        Traversable $iterator,
        int $flags = self::BYPASS_KEY,
        int $cachingIteratorFlags = CachingIterator::CATCH_GET_CHILD,
        int $mode = RecursiveIteratorIterator::SELF_FIRST
    ) {}

    /**
     * Rewind iterator
     * @return void
     */
    public function rewind(): void {}

    /**
     * Check validity
     * @return bool true if the current position is valid, otherwise false
     */
    public function valid(): bool {}

    /**
     * Get the key of the current element
     * @return string the current key prefixed and postfixed.
     */
    public function key(): mixed {}

    /**
     * Get current element
     * @return string the current element prefixed and postfixed.
     */
    public function current(): mixed {}

    /**
     * Move to next element
     * @return void
     */
    public function next(): void {}

    /**
     * Begin iteration
     * @return void
     */
    public function beginIteration(): void {}

    /**
     * End iteration
     * @return void
     */
    public function endIteration(): void {}

    /**
     * Has children
     * @return bool true if there are children, otherwise false
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
     * Get the prefix
     * @return string the string to place in front of current element
     */
    public function getPrefix(): string {}

    /**
     * Set postfix
     *
     * Sets postfix as used in RecursiveTreeIterator::getPostfix.
     * @param string $postfix
     */
    public function setPostfix(string $postfix): void {}

    /**
     * Set a part of the prefix
     * @param int $part One of the RecursiveTreeIterator::PREFIX_* constants.
     * @param string $value The value to assign to the part of the prefix specified in part.
     * @return void
     */
    public function setPrefixPart(
        int $part,
        string $value
    ): void {}

    /**
     * Get current entry
     * @return string the part of the tree built for the current element.
     */
    public function getEntry(): string {}

    /**
     * Get the postfix
     * @return string to place after the current element.
     */
    public function getPostfix(): string {}
}
