<?php
namespace Dom;

/**
 * This interface represents a known entity, either parsed or unparsed, in an XML document.
 *
 * This is the modern, spec-compliant equivalent of DOMEntity.
 * @since 8.4
 */
class Entity extends Node
{
    public ?string $publicId;

    public ?string $systemId;

    public ?string $notationName;
}
