<?php

class DOMNameSpaceNode
{
    public DOMNode|null $parentNode;

    public DOMDocument|null $ownerDocument;

    public string|null $namespaceURI;

    public string|null $localName;

    public string $prefix;

    public int $nodeType;

    public string|null $nodeValue;

    public string $nodeName;

    public ?DOMElement $parentElement;

    public bool $isConnected;

    /**
     * Forbids serialization unless serialization methods are implemented in a subclass
     * @since 8.1
     * @throws \Error Throws an Error exception when called.
     */
    public function __sleep(): array {}

    /**
     * Forbids unserialization unless unserialization methods are implemented in a subclass
     * @since 8.1
     * @throws \Error Throws an Error exception when called.
     */
    public function __wakeup(): void {}
}
