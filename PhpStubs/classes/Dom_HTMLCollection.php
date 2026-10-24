<?php
namespace Dom;

/**
 * Represents a static set of elements.
 * @since 8.4
 * @implements \IteratorAggregate<array-key, Element>
 */
class HTMLCollection implements \IteratorAggregate, \Countable
{
    public int $length;

    public function item(int $index): ?Element {}

    public function namedItem(string $key): ?Element {}

    public function count(): int {}

    /**
     * @return \Iterator<array-key, Element>
     */
    public function getIterator(): \Iterator {}
}
