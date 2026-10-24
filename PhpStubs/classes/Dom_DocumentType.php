<?php
namespace Dom;

/**
 * Each Dom\Document has a doctype attribute whose value is either null or a Dom\DocumentType
 * object.
 *
 * This is the modern, spec-compliant equivalent of DOMImplementation.
 * @since 8.4
 */
class DocumentType extends Node implements ChildNode
{
    public string $name;

    public DtdNamedNodeMap $entities;

    public DtdNamedNodeMap $notations;

    public string $publicId;

    public string $systemId;

    public ?string $internalSubset;

    public function remove(): void {}

    public function before(Node|string ...$nodes): void {}

    public function after(Node|string ...$nodes): void {}

    public function replaceWith(Node|string ...$nodes): void {}
}
