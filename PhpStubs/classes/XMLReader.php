<?php

/**
 * The XMLReader extension is an XML Pull parser. The reader acts as a
 * cursor going forward on the document stream and stopping at each node
 * on the way.
 * @property-read int $attributeCount The number of attributes on the node
 * @property-read string $baseURI The base URI of the node
 * @property-read int $depth Depth of the node in the tree, starting at 0
 * @property-read bool $hasAttributes Indicates if node has attributes
 * @property-read bool $hasValue Indicates if node has a text value
 * @property-read bool $isDefault Indicates if attribute is defaulted from DTD
 * @property-read bool $isEmptyElement Indicates if node is an empty element tag
 * @property-read string $localName The local name of the node
 * @property-read string $name The qualified name of the node
 * @property-read string $namespaceURI The URI of the namespace associated with the node
 * @property-read int $nodeType The node type for the node
 * @property-read string $prefix The prefix of the namespace associated with the node
 * @property-read string $value The text value of the node
 * @property-read string $xmlLang The xml:lang scope which the node resides
 */
class XMLReader
{
    /**
     * No node type
     */
    public const NONE = 0;

    /**
     * Start element
     */
    public const ELEMENT = 1;

    /**
     * Attribute node
     */
    public const ATTRIBUTE = 2;

    /**
     * Text node
     */
    public const TEXT = 3;

    /**
     * CDATA node
     */
    public const CDATA = 4;

    /**
     * Entity Reference node
     */
    public const ENTITY_REF = 5;

    /**
     * Entity Declaration node
     */
    public const ENTITY = 6;

    /**
     * Processing Instruction node
     */
    public const PI = 7;

    /**
     * Comment node
     */
    public const COMMENT = 8;

    /**
     * Document node
     */
    public const DOC = 9;

    /**
     * Document Type node
     */
    public const DOC_TYPE = 10;

    /**
     * Document Fragment node
     */
    public const DOC_FRAGMENT = 11;

    /**
     * Notation node
     */
    public const NOTATION = 12;

    /**
     * Whitespace node
     */
    public const WHITESPACE = 13;

    /**
     * Significant Whitespace node
     */
    public const SIGNIFICANT_WHITESPACE = 14;

    /**
     * End Element
     */
    public const END_ELEMENT = 15;

    /**
     * End Entity
     */
    public const END_ENTITY = 16;

    /**
     * XML Declaration node
     */
    public const XML_DECLARATION = 17;

    /**
     * Load DTD but do not validate
     */
    public const LOADDTD = 1;

    /**
     * Load DTD and default attributes but do not validate
     */
    public const DEFAULTATTRS = 2;

    /**
     * Load DTD and validate while parsing
     */
    public const VALIDATE = 3;

    /**
     * Substitute entities and expand references
     */
    public const SUBST_ENTITIES = 4;

    /**
     * The number of attributes on the node
     * @var int
     * @readonly
     */
    public int $attributeCount;

    /**
     * The base URI of the node
     * @var string
     * @readonly
     */
    public string $baseURI;

    /**
     * Depth of the node in the tree, starting at 0
     * @var int
     * @readonly
     */
    public int $depth;

    /**
     * Indicates if node has attributes
     * @var bool
     * @readonly
     */
    public bool $hasAttributes;

    /**
     * Indicates if node has a text value
     * @var bool
     * @readonly
     */
    public bool $hasValue;

    /**
     * Indicates if attribute is defaulted from DTD
     * @var bool
     * @readonly
     */
    public bool $isDefault;

    /**
     * Indicates if node is an empty element tag
     * @var bool
     * @readonly
     */
    public bool $isEmptyElement;

    /**
     * The local name of the node
     * @var string
     * @readonly
     */
    public string $localName;

    /**
     * The qualified name of the node
     * @var string
     * @readonly
     */
    public string $name;

    /**
     * The URI of the namespace associated with the node
     * @var string
     * @readonly
     */
    public string $namespaceURI;

    /**
     * The node type for the node
     * @var int
     * @readonly
     */
    public int $nodeType;

    /**
     * The prefix of the namespace associated with the node
     * @var string
     * @readonly
     */
    public string $prefix;

    /**
     * The text value of the node
     * @var string
     * @readonly
     */
    public string $value;

    /**
     * The xml:lang scope which the node resides
     * @var string
     * @readonly
     */
    public string $xmlLang;

    /**
     * Close the XMLReader input
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function close(): bool {}

    /**
     * Get the value of a named attribute
     * @param string $name The name of the attribute.
     * @return string|null The value of the attribute, or NULL if no attribute with the given name is found or not positioned on an element node.
     * @since 5.1
     */
    public function getAttribute(string $name): ?string {}

    /**
     * Get the value of an attribute by index
     * @param int $index The position of the attribute.
     * @return string|null The value of the attribute, or NULL if no attribute exists at index or not positioned of element.
     * @since 5.1
     */
    public function getAttributeNo(int $index): ?string {}

    /**
     * Get the value of an attribute by localname and URI
     * @param string $name The local name.
     * @param string $namespace The namespace URI.
     * @return string|null The value of the attribute, or NULL if no attribute with the given localName and namespaceURI is found or not positioned of element.
     * @since 5.1
     */
    public function getAttributeNs(
        string $name,
        string $namespace
    ): ?string {}

    /**
     * Indicates if specified property has been set
     * @param int $property One of the parser option constants.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function getParserProperty(int $property): bool {}

    /**
     * Indicates if the parsed document is valid
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function isValid(): bool {}

    /**
     * Lookup namespace for a prefix
     * @param string $prefix String containing the prefix.
     * @return string|null The value of the namespace, or NULL if no namespace exists.
     * @since 5.1
     */
    public function lookupNamespace(string $prefix): ?string {}

    /**
     * Move cursor to an attribute by index
     * @param int $index The position of the attribute.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function moveToAttributeNo(int $index): bool {}

    /**
     * Move cursor to a named attribute
     * @param string $name The name of the attribute.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function moveToAttribute(string $name): bool {}

    /**
     * Move cursor to a named attribute
     * @param string $name The local name.
     * @param string $namespace The namespace URI.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function moveToAttributeNs(
        string $name,
        string $namespace
    ): bool {}

    /**
     * Position cursor on the parent Element of current Attribute
     * @return bool TRUE if successful and FALSE if it fails or not positioned on Attribute when this method is called.
     * @since 5.1
     */
    public function moveToElement(): bool {}

    /**
     * Position cursor on the first Attribute
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function moveToFirstAttribute(): bool {}

    /**
     * Position cursor on the next Attribute
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function moveToNextAttribute(): bool {}

    /**
     * Set the URI containing the XML to parse
     * @param string $uri URI pointing to the document.
     * @param string $encoding [optional] The document encoding or NULL.
     * @param int $flags [optional] A bitmask of the LIBXML_* constants.
     * @return XMLReader|bool TRUE on success or FALSE on failure. If called statically, returns an XMLReader or FALSE on failure.
     * @since 5.1
     * @throws \ValueError Passing an invalid encoding will throw a ValueError. This method may be called statically, but prior to PHP 8.0.0, will issue an E_DEPRECATED error in this case.
     */
    public static function open(
        string $uri,
        string|null $encoding = null,
        int $flags = 0
    ) {}

    /**
     * Move to next node in document
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function read(): bool {}

    /**
     * Move cursor to next node skipping all subtrees
     * @param string $name [optional] The name of the next node to move to.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function next(string|null $name = null): bool {}

    /**
     * Retrieve XML from current node
     * @return string the contents of the current node as a string. Empty string on failure.
     */
    public function readInnerXml(): string {}

    /**
     * Retrieve XML from current node, including it self
     * @return string the contents of current node, including itself, as a string. Empty string on failure.
     */
    public function readOuterXml(): string {}

    /**
     * Reads the contents of the current node as a string
     * @return string the content of the current node as a string. Empty string on failure.
     */
    public function readString(): string {}

    /**
     * Validate document against XSD
     * @param string $filename The filename of the XSD schema.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setSchema(string|null $filename): bool {}

    /**
     * Set parser options
     * @param int $property One of the parser option constants.
     * @param bool $value If set to TRUE the option will be enabled otherwise will be disabled.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function setParserProperty(
        int $property,
        bool $value
    ): bool {}

    /**
     * Set the filename or URI for a RelaxNG Schema
     * @param string $filename filename or URI pointing to a RelaxNG Schema.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setRelaxNGSchema(string|null $filename): bool {}

    /**
     * Set the data containing a RelaxNG Schema
     * @param string $source String containing the RelaxNG Schema.
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.1
     */
    public function setRelaxNGSchemaSource(string|null $source): bool {}

    /**
     * Set the data containing the XML to parse
     * @param string $source String containing the XML to be parsed.
     * @param string $encoding [optional] The document encoding or NULL.
     * @param int $flags [optional] A bitmask of the LIBXML_* constants.
     * @return XMLReader|bool TRUE on success or FALSE on failure. If called statically, returns an XMLReader or FALSE on failure.
     * @since 5.1
     * @throws \ValueError Passing an invalid encoding will throw a ValueError. This method may be called statically, but prior to PHP 8.0.0, will issue an E_DEPRECATED error in this case.
     */
    public static function XML(
        string $source,
        string|null $encoding = null,
        int $flags = 0
    ) {}

    /**
     * Returns a copy of the current node as a DOM object
     * @param null|DOMNode $baseNode [optional]
     * @return DOMNode|false The resulting DOMNode or FALSE on error.
     * @since 5.1
     */
    public function expand(
        DOMNode|null $baseNode = null
    ): DOMNode|false {}

    /**
     * Creates an XMLReader from a URI to read from
     * @since 8.4
     * @throws \ValueError Passing an invalid encoding will throw a ValueError.
     */
    public static function fromUri(string $uri, ?string $encoding = null, int $flags = 0): static {}

    /**
     * Creates an XMLReader from a stream to read from
     * @since 8.4
     * @throws \ValueError Passing an invalid encoding will throw a ValueError.
     * @throws \TypeError Passing a resource that is not a stream to stream will throw a TypeError.
     */
    public static function fromStream($stream, ?string $encoding = null, int $flags = 0, ?string $documentUri = null): static {}

    /**
     * Creates an XMLReader from an XML string
     * @since 8.4
     * @throws \ValueError Passing an invalid encoding will throw a ValueError.
     */
    public static function fromString(string $source, ?string $encoding = null, int $flags = 0): static {}
}
