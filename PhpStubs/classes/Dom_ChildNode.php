<?php
namespace Dom;

/**
 * This is the modern, spec-compliant equivalent of DOMChildNode.
 * @since 8.4
 */
interface ChildNode
{
    /**
     * Removes the node
     * @return void No value is returned.
     */
    public function remove(): void;

    /**
     * Adds nodes before the node
     *
     * Adds the passed nodes before the node.
     * @param Node|string $nodes Nodes to be added before the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function before(Node|string ...$nodes): void;

    /**
     * Adds nodes after the node
     *
     * Adds the passed nodes after the node.
     * @param Node|string $nodes Nodes to be added after the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function after(Node|string ...$nodes): void;

    /**
     * Replaces the node with new nodes
     * @param Node|string $nodes The replacement nodes. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function replaceWith(Node|string ...$nodes): void;
}
