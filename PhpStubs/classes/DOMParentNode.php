<?php

/**
 * @property-read DOMElement|null $firstElementChild
 * @property-read DOMElement|null $lastElementChild
 * @property-read int $childElementCount
 * @since 8.0
 */
interface DOMParentNode
{
    /**
     * Appends one or many nodes to the list of children behind the last
     * child node.
     * @param DOMNode|string|null ...$nodes The nodes to append. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     * @since 8.0
     */
    public function append(...$nodes): void;

    /**
     * Prepends one or many nodes to the list of children before the first
     * child node.
     * @param DOMNode|string|null ...$nodes The nodes to prepend. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     * @since 8.0
     */
    public function prepend(...$nodes): void;

    /**
     * Replace children in node
     * @since 8.3
     */
    public function replaceChildren(...$nodes): void;
}
