<?php
namespace Dom;

/**
 * Represents the set of attributes on an element.
 * @since 8.4
 * @implements \IteratorAggregate<array-key, Attr>
 */
class NamedNodeMap implements \IteratorAggregate, \Countable
{
    public int $length;

    public function item(int $index): ?Attr {}

    public function getNamedItem(string $qualifiedName): ?Attr {}

    public function getNamedItemNS(?string $namespace, string $localName): ?Attr {}

    public function count(): int {}

    /**
     * @return \Iterator<array-key, Attr>
     */
    public function getIterator(): \Iterator {}
}
