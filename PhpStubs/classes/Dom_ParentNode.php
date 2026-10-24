<?php
namespace Dom;

/**
 * This is the modern, spec-compliant equivalent of DOMParentNode.
 * @since 8.4
 */
interface ParentNode
{
    /**
     * Appends nodes after the last child node
     *
     * Appends one or many nodes to the list of children after the last child node.
     * @param Node|string $nodes The nodes to append. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function append(Node|string ...$nodes): void;

    /**
     * Prepends nodes before the first child node
     *
     * Prepends one or many nodes to the list of children before the first child node.
     * @param Node|string $nodes The nodes to prepend. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function prepend(Node|string ...$nodes): void;

    /**
     * Replace children in node
     * @param Node|string $nodes The nodes replacing the children. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function replaceChildren(Node|string ...$nodes): void;

    /**
     * Returns the first element that matches the CSS selectors
     *
     * Returns the first element that matches the CSS selectors specified in selectors.
     * @param string $selectors A string containing one or more CSS selectors.
     * @return Element|null Returns the first Dom\Element that matches selectors. Returns null if no element matches.
     * @throws \DOMException Throws a DOMException with code Dom\SYNTAX_ERR when selectors is not a valid CSS selector string.
     */
    public function querySelector(string $selectors): ?Element;

    /**
     * Returns a collection of elements that match the CSS selectors
     *
     * Returns a collection of elements that match the CSS selectors specified in selectors.
     * @return NodeList<Element> Returns a static collection of elements that match the CSS selectors specified in selectors.
     */
    public function querySelectorAll(string $selectors): NodeList;
}
