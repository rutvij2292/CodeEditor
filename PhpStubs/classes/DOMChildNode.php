<?php

/**
 * @property-read DOMElement|null $previousElementSibling
 * @property-read DOMElement|null $nextElementSibling
 * @since 8.0
 */
interface DOMChildNode
{
    /**
     * Acts as a simpler version of DOMNode::removeChild().
     * @return void No value is returned.
     * @since 8.0
     */
    public function remove(): void;

    /**
     * Add passed node(s) before the current node
     * @param DOMNode|string|null ...$nodes Nodes to be added before the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     * @since 8.0
     */
    public function before(...$nodes): void;

    /**
     * Add passed node(s) after  the current node
     * @param DOMNode|string|null ...$nodes Nodes to be added after the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     * @since 8.0
     */
    public function after(...$nodes): void;

    /**
     * Replace current node with new node(s), a combination
     * of DOMChildNode::remove() + DOMChildNode::append().
     * @param DOMNode|string|null ...$nodes The replacement nodes. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     * @since 8.0
     */
    public function replaceWith(...$nodes): void;
}
