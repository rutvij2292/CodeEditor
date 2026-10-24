<?php
namespace Dom;

/**
 * This class provides a number of methods for performing operations that are independent of any
 * particular instance of the document object model.
 *
 * This is the modern, spec-compliant equivalent of DOMImplementation.
 * @since 8.4
 */
class Implementation
{
    public function createDocumentType(string $qualifiedName, string $publicId, string $systemId): DocumentType {}

    public function createDocument(?string $namespace, string $qualifiedName, ?DocumentType $doctype = null): XMLDocument {}

    public function createHTMLDocument(?string $title = null): HTMLDocument {}
}
