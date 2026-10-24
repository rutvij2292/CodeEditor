<?php
namespace Dom;

/**
 * Dom\Attr represents an attribute in the Dom\Element object.
 *
 * This is the modern, spec-compliant equivalent of DOMAttr.
 * @since 8.4
 */
class Attr extends Node
{
    public ?string $namespaceURI;

    public ?string $prefix;

    public string $localName;

    public string $name;

    public string $value;

    public ?Element $ownerElement;

    public bool $specified;

    /**
     * Checks if attribute is a defined ID
     *
     * This function checks if the attribute is a defined ID. According to the DOM standard this
     * requires a DTD which defines the attribute ID to be of type ID. To utilise this method the
     * document must be validated at parse time by passing LIBXML_DTDVALID as an option.
     * @return bool Returns true if this attribute is a defined ID, false otherwise.
     */
    public function isId(): bool {}

    /**
     * Changes the qualified name or namespace of an attribute
     *
     * This method changes the qualified name or namespace of an attribute.
     * @param string|null $namespaceURI The new namespace URI of the attribute.
     * @param string $qualifiedName The new qualified name of the attribute.
     * @return void No value is returned.
     * @throws \DOMException DOMException with code Dom\NAMESPACE_ERR Raised if there is an error with the namespace, as determined by qualifiedName. DOMException with code Dom\INVALID_MODIFICATION_ERR Raised if there already exists an attribute in the element with the same qualified name.
     */
    public function rename(?string $namespaceURI, string $qualifiedName): void {}
}
