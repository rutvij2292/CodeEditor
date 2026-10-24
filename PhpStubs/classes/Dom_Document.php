<?php
namespace Dom;

/**
 * Represents an entire HTML or XML document; serves as the root of the document tree.
 *
 * This is the modern, spec-compliant equivalent of DOMDocument. It is the base class for
 * Dom\XMLDocument and Dom\HTMLDocument.
 * @since 8.4
 */
class Document extends Node implements ParentNode
{
    /**
     * @readonly
     */
    public Implementation $implementation;

    public string $URL;

    public string $documentURI;

    public string $characterSet;

    public string $charset;

    public string $inputEncoding;

    public ?DocumentType $doctype;

    public ?Element $documentElement;

    /**
     * @since 8.5
     */
    public \Dom\HTMLCollection $children;

    public function getElementsByTagName(string $qualifiedName): HTMLCollection {}

    public function getElementsByTagNameNS(?string $namespace, string $localName): HTMLCollection {}

    public function createElement(string $localName): Element {}

    public function createElementNS(?string $namespace, string $qualifiedName): Element {}

    public function createDocumentFragment(): DocumentFragment {}

    public function createTextNode(string $data): Text {}

    public function createCDATASection(string $data): CDATASection {}

    public function createComment(string $data): Comment {}

    public function createProcessingInstruction(string $target, string $data): ProcessingInstruction {}

    public function importNode(?Node $node, bool $deep = false): Node {}

    public function adoptNode(Node $node): Node {}

    public function createAttribute(string $localName): Attr {}

    public function createAttributeNS(?string $namespace, string $qualifiedName): Attr {}

    public ?Element $firstElementChild;

    public ?Element $lastElementChild;

    public int $childElementCount;

    public function getElementById(string $elementId): ?Element {}

    public function registerNodeClass(string $baseClass, ?string $extendedClass): void {}

    public function schemaValidate(string $filename, int $flags = 0): bool {}

    public function schemaValidateSource(string $source, int $flags = 0): bool {}

    public function relaxNgValidate(string $filename): bool {}

    public function relaxNgValidateSource(string $source): bool {}

    public function append(Node|string ...$nodes): void {}

    public function prepend(Node|string ...$nodes): void {}

    public function replaceChildren(Node|string ...$nodes): void {}

    public function importLegacyNode(\DOMNode $node, bool $deep = false): Node {}

    public function querySelector(string $selectors): ?Element {}

    /**
     * @return NodeList<Element>
     */
    public function querySelectorAll(string $selectors): NodeList {}

    /**
     * @since 8.5
     */
    public function getElementsByClassName(string $classNames): HTMLCollection {}

    public ?HTMLElement $body;

    public ?HTMLElement $head;

    public string $title;
}
