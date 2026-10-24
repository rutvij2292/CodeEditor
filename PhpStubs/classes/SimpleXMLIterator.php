<?php

/**
 * The SimpleXMLIterator provides recursive iteration over all nodes of a SimpleXMLElement object.
 */
class SimpleXMLIterator extends SimpleXMLElement implements RecursiveIterator, Countable, Stringable
{
    /**
     * Rewind to the first element
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Check whether the current element is valid
     * @return bool TRUE if the current element is valid, otherwise FALSE
     */
    public function valid(): bool {}

    /**
     * Returns the current element
     * @return SimpleXMLElement the current element as a SimpleXMLElement object.
     */
    public function current(): SimpleXMLElement {}

    /**
     * Return current key
     * @return string|false the XML tag name of the element referenced by the current SimpleXMLIterator object or FALSE
     */
    public function key(): string {}

    /**
     * Move to next element
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Checks whether the current element has sub elements.
     * @return bool TRUE if the current element has sub-elements, otherwise FALSE
     */
    public function hasChildren(): bool {}

    /**
     * Returns the sub-elements of the current element
     * @return SimpleXMLElement|null a SimpleXMLElement object containing the sub-elements of the current element.
     */
    public function getChildren(): SimpleXMLElement|null {}

    /**
     * Returns the string content
     * @return string the string content on success or an empty string on failure.
     * @since 5.3
     */
    public function __toString(): string {}

    /**
     * Counts the children of an element
     * @return int the number of elements of an element.
     */
    public function count(): int {}
}
