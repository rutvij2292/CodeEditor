<?php
namespace Dom;

/**
 * This represents immutable information about namespaces of an element. This decouples namespaces
 * from attributes, which was incorrectly intertwined for the old DOM classes.
 * @since 8.4
 */
final readonly class NamespaceInfo
{
    public readonly ?string $prefix;

    public readonly ?string $namespaceURI;

    public readonly Element $element;

    private function __construct() {}
}
