<?php
namespace Dom;

/**
 * Represents an element.
 *
 * This is the modern, spec-compliant equivalent of DOMElement.
 * @since 8.4
 */
class Element extends Node implements ParentNode, ChildNode
{
    public ?string $namespaceURI;

    public ?string $prefix;

    public string $localName;

    public string $tagName;

    public string $id;

    public string $className;

    /**
     * @since 8.5
     */
    public \Dom\HTMLCollection $children;

    /**
     * @readonly
     */
    public TokenList $classList;

    public function hasAttributes(): bool {}

    public NamedNodeMap $attributes;

    public function getAttributeNames(): array {}

    public function getAttribute(string $qualifiedName): ?string {}

    public function getAttributeNS(?string $namespace, string $localName): ?string {}

    public function setAttribute(string $qualifiedName, string $value): void {}

    public function setAttributeNS(?string $namespace, string $qualifiedName, string $value): void {}

    public function removeAttribute(string $qualifiedName): void {}

    public function removeAttributeNS(?string $namespace, string $localName): void {}

    public function toggleAttribute(string $qualifiedName, ?bool $force = null): bool {}

    public function hasAttribute(string $qualifiedName): bool {}

    public function hasAttributeNS(?string $namespace, string $localName): bool {}

    public function getAttributeNode(string $qualifiedName): ?Attr {}

    public function getAttributeNodeNS(?string $namespace, string $localName): ?Attr {}

    public function setAttributeNode(Attr $attr): ?Attr {}

    public function setAttributeNodeNS(Attr $attr): ?Attr {}

    public function removeAttributeNode(Attr $attr): Attr {}

    public function getElementsByTagName(string $qualifiedName): HTMLCollection {}

    public function getElementsByTagNameNS(?string $namespace, string $localName): HTMLCollection {}

    public function insertAdjacentElement(AdjacentPosition $where, Element $element): ?Element {}

    public function insertAdjacentText(AdjacentPosition $where, string $data): void {}

    public ?Element $firstElementChild;

    public ?Element $lastElementChild;

    public int $childElementCount;

    public ?Element $previousElementSibling;

    public ?Element $nextElementSibling;

    public function setIdAttribute(string $qualifiedName, bool $isId): void {}

    public function setIdAttributeNS(?string $namespace, string $qualifiedName, bool $isId): void {}

    public function setIdAttributeNode(Attr $attr, bool $isId): void {}

    public function remove(): void {}

    public function before(Node|string ...$nodes): void {}

    public function after(Node|string ...$nodes): void {}

    public function replaceWith(Node|string ...$nodes): void {}

    public function append(Node|string ...$nodes): void {}

    public function prepend(Node|string ...$nodes): void {}

    public function replaceChildren(Node|string ...$nodes): void {}

    public function querySelector(string $selectors): ?Element {}

    /**
     * @return NodeList<Element>
     */
    public function querySelectorAll(string $selectors): NodeList {}

    public function closest(string $selectors): ?Element {}

    public function matches(string $selectors): bool {}

    public string $innerHTML;

    public string $outerHTML;

    public string $substitutedNodeValue;

    /**
     * @return list<NamespaceInfo>
     */
    public function getInScopeNamespaces(): array {}

    /**
     * @return list<NamespaceInfo>
     */
    public function getDescendantNamespaces(): array {}

    public function rename(?string $namespaceURI, string $qualifiedName): void {}

    /**
     * @since 8.5
     */
    public function getElementsByClassName(string $classNames): HTMLCollection {}

    /**
     * @since 8.5
     */
    public function insertAdjacentHTML(\Dom\AdjacentPosition $where, string $string): void {}
}
