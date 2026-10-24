<?php

/**
 * The DOMImplementation interface provides a number
 * of methods for performing operations that are independent of any
 * particular instance of the document object model.
 */
class DOMImplementation
{
    /**
     * @param string $feature
     * @param string $version
     * @return mixed
     * @removed 8.4
     */
    public function getFeature(
        string $feature,
        string $version
    ): never {}

    /**
     * Test if the DOM implementation implements a specific feature
     * @param string $feature The feature to test.
     * @param string $version The version number of the feature to test. In level 2, this can be either 2.0 or 1.0.
     * @return bool true on success or false on failure.
     */
    public function hasFeature(
        string $feature,
        string $version
    ): bool {}

    /**
     * Creates an empty DOMDocumentType object
     * @param string $qualifiedName The qualified name of the document type to create.
     * @param string $publicId The external subset public identifier.
     * @param string $systemId The external subset system identifier.
     * @return DOMDocumentType|false A new DOMDocumentType node with its ownerDocument set to null.
     * @throws DOMException If there is an error with the namespace
     */
    public function createDocumentType(
        string $qualifiedName,
        string $publicId = '',
        string $systemId = ''
    ) {}

    /**
     * Creates a DOMDocument object of the specified type with its document element
     * @param string|null $namespace The namespace URI of the document element to create.
     * @param string $qualifiedName The qualified name of the document element to create.
     * @param DOMDocumentType|null $doctype The type of document to create or null.
     * @return DOMDocument|false A new DOMDocument object. If namespaceURI, qualifiedName, and doctype are null, the returned DOMDocument is empty with no document element.
     * @throws DOMException If $doctype has already been used with adifferent document or was created from a different implementation. If there is an error with the namespace, as determined by $namespace and $qualifiedName.
     */
    public function createDocument(
        ?string $namespace = null,
        string $qualifiedName = '',
        DOMDocumentType|null $doctype = null
    ): DOMDocument|false {}
}
