<?php
namespace Dom;

/**
 * Represents a live list of nodes.
 *
 * This is the modern, spec-compliant equivalent of DOMNodeList.
 * @since 8.4
 * @template TNode of Node Should be template-covariant but DocBlock::getTagsByName() does not support it
 * @implements \IteratorAggregate<int, TNode>
 */
class NodeList implements \IteratorAggregate, \Countable
{
    public int $length;

    public function count(): int {}

    /**
     * @return \Iterator<int, TNode>
     */
    public function getIterator(): \Iterator {}

    /**
     * @return TNode|null
     */
    public function item(int $index): ?Node {}
}
