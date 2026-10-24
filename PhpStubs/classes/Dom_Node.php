<?php
namespace Dom;

/**
 * This is the modern, spec-compliant equivalent of DOMNode.
 * @since 8.4
 */
class Node
{
    final private function __construct() {}

    public int $nodeType;

    public string $nodeName;

    public string $baseURI;

    public bool $isConnected;

    public ?Document $ownerDocument;

    public function getRootNode(array $options = []): Node {}

    public ?Node $parentNode;

    public ?Element $parentElement;

    public function hasChildNodes(): bool {}

    /**
     * @var NodeList<Node>
     */
    public NodeList $childNodes;

    public ?Node $firstChild;

    public ?Node $lastChild;

    public ?Node $previousSibling;

    public ?Node $nextSibling;

    public ?string $nodeValue;

    public ?string $textContent;

    public function normalize(): void {}

    public function cloneNode(bool $deep = false): Node {}

    public function isEqualNode(?Node $otherNode): bool {}

    public function isSameNode(?Node $otherNode): bool {}

    public const int DOCUMENT_POSITION_DISCONNECTED = 0x01;

    public const int DOCUMENT_POSITION_PRECEDING = 0x02;

    public const int DOCUMENT_POSITION_FOLLOWING = 0x04;

    public const int DOCUMENT_POSITION_CONTAINS = 0x08;

    public const int DOCUMENT_POSITION_CONTAINED_BY = 0x10;

    public const int DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20;

    public function compareDocumentPosition(Node $other): int {}

    public function contains(?Node $other): bool {}

    public function lookupPrefix(?string $namespace): ?string {}

    public function lookupNamespaceURI(?string $prefix): ?string {}

    public function isDefaultNamespace(?string $namespace): bool {}

    public function insertBefore(Node $node, ?Node $child): Node {}

    public function appendChild(Node $node): Node {}

    public function replaceChild(Node $node, Node $child): Node {}

    public function removeChild(Node $child): Node {}

    public function getLineNo(): int {}

    public function getNodePath(): string {}

    public function C14N(bool $exclusive = false, bool $withComments = false, ?array $xpath = null, ?array $nsPrefixes = null): string|false {}

    public function C14NFile(string $uri, bool $exclusive = false, bool $withComments = false, ?array $xpath = null, ?array $nsPrefixes = null): int|false {}

    public function __sleep(): array {}

    public function __wakeup(): void {}
}
