<?php

/**
 * The DOMNamedNodeMap class
 * @property-read int $length The number of nodes in the map. The range of valid child node indices is 0 to length - 1 inclusive.
 * @template-covariant TNode of DOMNode
 * @implements IteratorAggregate<string, TNode>
 */
class DOMNamedNodeMap implements IteratorAggregate, Countable
{
    /**
     * @var int The number of nodes in the map. The valid child node indices range from 0 to length - 1 inclusive.
     * @readonly
     */
    public int $length;

    /**
     * Retrieves a node specified by name
     * @param string $qualifiedName The nodeName of the node to retrieve.
     * @return TNode|null A node (of any type) with the specified nodeName, or null if no node is found.
     */
    public function getNamedItem(string $qualifiedName): ?DOMNode {}

    /**
     * @removed 8.0
     * @param DOMNode $arg
     * @return void
     */
    public function setNamedItem(DOMNode $arg) {}

    /**
     * @removed 8.0
     * @param $name [optional]
     */
    public function removeNamedItem($name) {}

    /**
     * Retrieves a node specified by index
     * @param int $index Index into this map.
     * @return DOMNode|null The node at the indexth position in the map, or null if that is not a valid index (greater than or equal to the number of nodes in this map).
     */
    public function item(
        int $index
    ): ?DOMNode {}

    /**
     * Retrieves a node specified by local name and namespace URI
     * @param string $namespace The namespace URI of the node to retrieve.
     * @param string $localName The local name of the node to retrieve.
     * @return TNode|null A node (of any type) with the specified local name and namespace URI, or null if no node is found.
     */
    public function getNamedItemNS(
        ?string $namespace,
        string $localName
    ): ?DOMNode {}

    /**
     * @removed 8.0
     * @param DOMNode $arg [optional]
     */
    public function setNamedItemNS(DOMNode $arg) {}

    /**
     * @removed 8.0
     * @param $namespace [optional]
     * @param $localName [optional]
     */
    public function removeNamedItemNS($namespace, $localName) {}

    /**
     * Get number of nodes in the map
     *
     * Gets the number of nodes in the map.
     * @return int<0,max> Returns the number of nodes in the map, which is identical to the length property.
     * @since 7.2
     */
    public function count(): int {}

    /**
     * Retrieve an external iterator
     *
     * Returns an external iterator for the named node map.
     * @return Iterator<string, TNode> An instance of an object implementing Iterator or Traversable
     * @since 8.0
     */
    public function getIterator(): Iterator {}
}
