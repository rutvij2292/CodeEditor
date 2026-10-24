<?php

/**
 * The DOMNodeList class
 * @template-covariant TNode of DOMNode|DOMNameSpaceNode
 * @implements IteratorAggregate<int, TNode>
 */
class DOMNodeList implements IteratorAggregate, Countable
{
    /**
     * @var int The number of nodes in the list. The range of valid child node indices is 0 to length - 1 inclusive.
     */
    public int $length;

    /**
     * Retrieves a node specified by index
     * @param int $index Index of the node into the collection. The range of valid child node indices is 0 to length - 1 inclusive.
     * @return TNode|null The node at the indexth position in the DOMNodeList, or null if that is not a valid index.
     */
    public function item(int $index) {}

    /**
     * Get number of nodes in the list
     *
     * Gets the number of nodes in the list.
     * @return int<0, max> Returns the number of nodes in the list, which is identical to the length property.
     * @since 7.2
     */
    public function count(): int {}

    /**
     * Retrieve an external iterator
     *
     * Returns an external iterator for the node list.
     * @return Iterator<int, TNode> An instance of an object implementing Iterator or Traversable
     * @since 8.0
     */
    public function getIterator(): Iterator {}
}
