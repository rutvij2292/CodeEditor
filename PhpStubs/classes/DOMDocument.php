<?php

/**
 * The DOMDocument class represents an entire HTML or XML
 * document; serves as the root of the document tree.
 */
class DOMDocument extends DOMNode implements DOMParentNode
{
    /**
     * @var string|null
     */
    public string|null $actualEncoding;

    /**
     * @var DOMConfiguration
     * @see DOMDocument::normalizeDocument()
     */
    public mixed $config;

    /**
     * @var DOMDocumentType The Document Type Declaration associated with this document.
     */
    public DOMDocumentType|null $doctype;

    /**
     * @var DOMElement This is a convenience attribute that allows direct access to the child node that is the document element of the document.
     */
    public DOMElement|null $documentElement;

    /**
     * @var string|null The location of the document or NULL if undefined.
     */
    public string|null $documentURI;

    /**
     * @var string|null Encoding of the document, as specified by the XML declaration. This attribute is not present in the final DOM Level 3 specification, but is the only way of manipulating XML document encoding in this implementation.
     */
    public string|null $encoding;

    /**
     * @var bool Nicely formats output with indentation and extra space.
     */
    public bool $formatOutput;

    /**
     * @var DOMImplementation The DOMImplementation object that handles this document.
     */
    public DOMImplementation $implementation;

    /**
     * @var bool Do not remove redundant white space. Default to TRUE.
     */
    public bool $preserveWhiteSpace = true;

    /**
     * @var bool Proprietary. Enables recovery mode, i.e. trying to parse non-well formed documents. This attribute is not part of the DOM specification and is specific to libxml.
     */
    public bool $recover;

    /**
     * @var bool Set it to TRUE to load external entities from a doctype declaration. This is useful for including character entities in your XML document.
     */
    public bool $resolveExternals;

    /**
     * @var bool
     * @deprecated
     */
    public bool $standalone;

    /**
     * @var bool Throws DOMException on errors. Default to TRUE.
     */
    public bool $strictErrorChecking = true;

    /**
     * @var bool Proprietary. Whether or not to substitute entities. This attribute is not part of the DOM specification and is specific to libxml.
     */
    public bool $substituteEntities;

    /**
     * @var bool Loads and validates against the DTD. Default to FALSE.
     */
    public bool $validateOnParse = false;

    /**
     * @var string
     * @deprecated
     */
    public string|null $version;

    /**
     * @var string|null An attribute specifying, as part of the XML declaration, the encoding of this document. This is NULL when unspecified or when it is not known, such as when the Document was created in memory.
     */
    public string|null $xmlEncoding;

    /**
     * @var bool An attribute specifying, as part of the XML declaration, whether this document is standalone. This is FALSE when unspecified.
     */
    public bool $xmlStandalone;

    /**
     * @var string|null An attribute specifying, as part of the XML declaration, the version number of this document. If there is no declaration and if this document supports the "XML" feature, the value is "1.0".
     */
    public string|null $xmlVersion;

    public int $childElementCount;

    public DOMElement|null $lastElementChild;

    public DOMElement|null $firstElementChild;

    /**
     * @var null The DOMDocument object associated with this node, or NULL if this node is a DOMDocument.
     */
    public DOMDocument|null $ownerDocument;

    /**
     * Create new element node
     * @param string $localName The tag name of the element.
     * @param string $value [optional] The value of the element. By default, an empty element will be created. You can also set the value later with DOMElement->nodeValue.
     * @return DOMElement|false A new instance of class DOMElement or false if an error occurred.
     * @throws DOMException If invalid $localName
     */
    public function createElement(
        string $localName,
        string $value = ''
    ) {}

    /**
     * Create new document fragment
     * @return DOMDocumentFragment The new DOMDocumentFragment. Prior to PHP 8.1, false was returned if an error occurred.
     */
    public function createDocumentFragment(): DOMDocumentFragment {}

    /**
     * Create new text node
     * @param string $data The content of the text.
     * @return DOMText The new DOMText. Prior to PHP 8.1, false was returned if an error occurred.
     */
    public function createTextNode(string $data): DOMText {}

    /**
     * Create new comment node
     * @param string $data The content of the comment.
     * @return DOMComment The new DOMComment. Prior to PHP 8.1, false was returned if an error occurred.
     */
    public function createComment(string $data): DOMComment {}

    /**
     * Create new cdata node
     * @param string $data The content of the cdata.
     * @return DOMCDATASection|false The new DOMCDATASection or false if an error occurred.
     */
    public function createCDATASection(string $data) {}

    /**
     * Creates new PI node
     * @param string $target The target of the processing instruction.
     * @param string $data The content of the processing instruction.
     * @return DOMProcessingInstruction|false The new DOMProcessingInstruction or false if an error occurred.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INVALID_CHARACTER_ERR Raised if target contains an invalid character.
     */
    public function createProcessingInstruction(
        string $target,
        string $data = ''
    ) {}

    /**
     * Create new attribute
     * @param string $localName The name of the attribute.
     * @return DOMAttr|false The new DOMAttr or false if an error occurred.
     * @throws DOMException If invalid $localName
     */
    public function createAttribute(string $localName) {}

    /**
     * Create new entity reference node
     * @param string $name The content of the entity reference, e.g. the entity reference minus the leading & and the trailing ; characters.
     * @return DOMEntityReference|false The new DOMEntityReference or false if an error occurred.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INVALID_CHARACTER_ERR Raised if name contains an invalid character.
     */
    public function createEntityReference(string $name) {}

    /**
     * Searches for all elements with given tag name
     * @param string $qualifiedName The name of the tag to match on. The special value * matches all tags.
     * @return DOMNodeList<DOMElement> A new DOMNodeList object containing all the matched elements.
     */
    public function getElementsByTagName(string $qualifiedName): DOMNodeList {}

    /**
     * Import node into current document
     * @param DOMNode $node The node to import.
     * @param bool $deep If set to true, this method will recursively import the subtree under the importedNode. To copy the nodes attributes deep needs to be set to true
     * @return DOMNode|false The copied node or false, if it cannot be copied.
     * @throws \DOMException DOMException is thrown if node cannot be imported.
     */
    public function importNode(
        DOMNode $node,
        bool $deep = false
    ) {}

    /**
     * Create new element node with an associated namespace
     * @param string|null $namespace The URI of the namespace.
     * @param string $qualifiedName The qualified name of the element, as prefix:tagname.
     * @param string $value [optional] The value of the element. By default, an empty element will be created. You can also set the value later with DOMElement->nodeValue.
     * @return DOMElement|false The new DOMElement or false if an error occurred.
     * @throws DOMException If invalid $namespace or $qualifiedName
     */
    public function createElementNS(
        string|null $namespace,
        string $qualifiedName,
        string $value = ''
    ) {}

    /**
     * Create new attribute node with an associated namespace
     * @param string|null $namespace The URI of the namespace.
     * @param string $qualifiedName The tag name and prefix of the attribute, as prefix:tagname.
     * @return DOMAttr|false The new DOMAttr or false if an error occurred.
     * @throws DOMException If invalid $namespace or $qualifiedName
     */
    public function createAttributeNS(
        string|null $namespace,
        string $qualifiedName
    ) {}

    /**
     * Searches for all elements with given tag name in specified namespace
     * @param string $namespace The namespace URI of the elements to match on. The special value * matches all namespaces.
     * @param string $localName The local name of the elements to match on. The special value * matches all local names.
     * @return DOMNodeList<DOMElement> A new DOMNodeList object containing all the matched elements.
     */
    public function getElementsByTagNameNS(
        string|null $namespace,
        string $localName
    ): DOMNodeList {}

    /**
     * Searches for an element with a certain id
     * @param string $elementId The unique id value for an element.
     * @return DOMElement|null The DOMElement or null if the element is not found.
     */
    public function getElementById(string $elementId): ?DOMElement {}

    /**
     * Transfer a node from another document
     *
     * Transfer a node from another document into the current document.
     * @param DOMNode $node The node to transfer.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NOT_SUPPORTED_ERR Raised if the node type is not supported for document transfers.
     */
    public function adoptNode(DOMNode $node): DOMNode|false {}

    /**
     * {@inheritDoc}
     */
    public function append(...$nodes): void {}

    /**
     * {@inheritDoc}
     */
    public function prepend(...$nodes): void {}

    /**
     * @since 8.3 {@inheritDoc}
     */
    public function replaceChildren(...$nodes): void {}

    /**
     * Normalizes the document
     * @return void No value is returned.
     */
    public function normalizeDocument(): void {}

    /**
     * @param DOMNode $node
     * @param $namespace
     * @param $qualifiedName
     * @removed 8.0
     */
    public function renameNode(DOMNode $node, $namespace, $qualifiedName) {}

    /**
     * Load XML from a file
     * @param string $filename The path to the XML document.
     * @param int $options [optional] Bitwise OR of the libxml option constants.
     * @return DOMDocument|bool true on success or false on failure. Prior to PHP 8.3 if called statically, returns a DOMDocument and issues E_STRICT warning.
     */
    public function load(
        string $filename,
        int $options = 0
    ): bool {}

    /**
     * Dumps the internal XML tree back into a file
     * @param string $filename The path to the saved XML document.
     * @param int $options [optional] Additional Options. Currently only LIBXML_NOEMPTYTAG is supported.
     * @return int|false the number of bytes written or false if an error occurred.
     */
    public function save(
        string $filename,
        int $options = null
    ): int|false {}

    /**
     * Load XML from a string
     * @param string $source The string containing the XML.
     * @param int $options [optional] Bitwise OR of the libxml option constants.
     * @return DOMDocument|bool true on success or false on failure. Prior to PHP 8.3 if called statically, returns a DOMDocument and issues E_STRICT warning.
     */
    public function loadXML(
        string $source,
        int $options = 0
    ): bool {}

    /**
     * Dumps the internal XML tree back into a string
     * @param null|DOMNode $node [optional] Use this parameter to output only a specific node without XML declaration rather than the entire document.
     * @param int $options [optional] Additional Options. Currently only LIBXML_NOEMPTYTAG is supported.
     * @return string|false the XML, or false if an error occurred.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_WRONG_DOCUMENT_ERR Raised if node is from another document.
     */
    public function saveXML(
        DOMNode|null $node = null,
        int $options = 0
    ): string|false {}

    /**
     * Creates a new DOMDocument object
     * @param string $version [optional] The version number of the document as part of the XML declaration.
     * @param string $encoding [optional] The encoding of the document as part of the XML declaration.
     */
    public function __construct(
        string $version = '1.0',
        string $encoding = ''
    ) {}

    /**
     * Validates the document based on its DTD
     * @return bool true on success or false on failure. If the document have no DTD attached, this method will return false.
     */
    public function validate(): bool {}

    /**
     * Substitutes XIncludes in a DOMDocument Object
     * @param int $options [optional] libxml parameters. Available since PHP 5.1.0 and Libxml 2.6.7.
     * @return int|false the number of XIncludes in the document.
     */
    public function xinclude(int $options = 0): int|false {}

    /**
     * Load HTML from a string
     * @param string $source The HTML string.
     * @param int $options [optional] Since PHP 5.4.0 and Libxml 2.6.0, you may also use the options parameter to specify additional Libxml parameters.
     * @return DOMDocument|bool true on success or false on failure. Prior to PHP 8.3 if called statically, returns a DOMDocument and issues E_STRICT warning.
     */
    public function loadHTML(
        string $source,
        int $options = 0
    ): bool {}

    /**
     * Load HTML from a file
     * @param string $filename The path to the HTML file.
     * @param int $options [optional] Since PHP 5.4.0 and Libxml 2.6.0, you may also use the options parameter to specify additional Libxml parameters.
     * @return DOMDocument|bool true on success or false on failure. Prior to PHP 8.3 if called statically, returns a DOMDocument and issues E_STRICT warning.
     */
    public function loadHTMLFile(
        string $filename,
        int $options = 0
    ): bool {}

    /**
     * Dumps the internal document into a string using HTML formatting
     * @param null|DOMNode $node [optional] parameter to output a subset of the document.
     * @return string|false The HTML, or false if an error occurred.
     */
    public function saveHTML(DOMNode|null $node = null): string|false {}

    /**
     * Dumps the internal document into a file using HTML formatting
     * @param string $filename The path to the saved HTML document.
     * @return int|false the number of bytes written or false if an error occurred.
     */
    public function saveHTMLFile(string $filename): int|false {}

    /**
     * Validates a document based on a schema
     * @param string $filename The path to the schema.
     * @param int $flags A bitmask of Libxml schema validation flags. Currently the only supported value is LIBXML_SCHEMA_CREATE. Available since Libxml 2.6.14.
     * @return bool true on success or false on failure.
     */
    public function schemaValidate(
        string $filename,
        int $flags = null
    ): bool {}

    /**
     * Validates a document based on a schema
     * @param string $source A string containing the schema.
     * @param int $flags [optional] A bitmask of Libxml schema validation flags. Currently the only supported value is LIBXML_SCHEMA_CREATE. Available since PHP 5.5.2 and Libxml 2.6.14.
     * @return bool true on success or false on failure.
     */
    public function schemaValidateSource(
        string $source,
        int $flags = 0
    ): bool {}

    /**
     * Performs relaxNG validation on the document
     * @param string $filename The RNG file.
     * @return bool true on success or false on failure.
     */
    public function relaxNGValidate(string $filename): bool {}

    /**
     * Performs relaxNG validation on the document
     * @param string $source A string containing the RNG schema.
     * @return bool true on success or false on failure.
     */
    public function relaxNGValidateSource(string $source): bool {}

    /**
     * Register extended class used to create base node type
     * @param string $baseClass The DOM class that you want to extend. You can find a list of these classes in the chapter introduction.
     * @param string $extendedClass Your extended class name. If null is provided, any previously registered class extending baseclass will be removed.
     * @return bool true on success or false on failure.
     */
    public function registerNodeClass(
        string $baseClass,
        string|null $extendedClass
    ): bool {}
}
