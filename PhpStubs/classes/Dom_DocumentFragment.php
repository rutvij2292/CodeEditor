<?php
namespace Dom;

/**
 * This represents a document fragment, which can be used as a container for other nodes.
 *
 * This is the modern, spec-compliant equivalent of DOMDocumentFragment.
 * @since 8.4
 */
class DocumentFragment extends Node implements ParentNode
{
    public ?Element $firstElementChild;

    public ?Element $lastElementChild;

    public int $childElementCount;

    /**
     * @since 8.5
     */
    public \Dom\HTMLCollection $children;

    public function appendXml(string $data): bool {}

    public function append(Node|string ...$nodes): void {}

    public function prepend(Node|string ...$nodes): void {}

    public function replaceChildren(Node|string ...$nodes): void {}

    public function querySelector(string $selectors): ?Element {}

    /**
     * @return NodeList<Element>
     */
    public function querySelectorAll(string $selectors): NodeList {}
}
