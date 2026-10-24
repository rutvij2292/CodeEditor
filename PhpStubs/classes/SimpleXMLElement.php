<?php

/**
 * Represents an element in an XML document.
 */
class SimpleXMLElement implements Traversable, ArrayAccess, Countable, Iterator, Stringable, RecursiveIterator
{
    /**
     * Creates a new SimpleXMLElement object
     * @param string $data A well-formed XML string or the path or URL to an XML document if data_is_url is TRUE.
     * @param int $options Optionally used to specify additional Libxml parameters.
     * @param bool $dataIsURL By default, data_is_url is FALSE. Use TRUE to specify that data is a path or URL to an XML document instead of string data.
     * @param string $namespaceOrPrefix Namespace prefix or URI.
     * @param bool $isPrefix TRUE if ns is a prefix, FALSE if it's a URI; defaults to FALSE.
     * @throws Exception if the XML data could not be parsed.
     * @since 5.0
     */
    public function __construct(
        string $data,
        int $options = 0,
        bool $dataIsURL = false,
        string $namespaceOrPrefix = "",
        bool $isPrefix = false
    ) {}

    /**
     * Provides access to element's children
     * private Method not callable directly, stub exists for typehint only
     * @param string $name child name
     * @return static
     */
    private function __get($name) {}

    /**
     * Return a well-formed XML string based on SimpleXML element
     * @param string $filename [optional] If specified, the function writes the data to the file rather than returning it.
     * @return string|bool If the filename isn't specified, this function returns a string on success and FALSE on error. If the parameter is specified, it returns TRUE if the file was written successfully and FALSE otherwise.
     * @since 5.0
     */
    public function asXML(string|null $filename = null): string|bool {}

    /**
     * Alias of SimpleXMLElement::asXML
     * Return a well-formed XML string based on SimpleXML element
     * @param string $filename [optional] If specified, the function writes the data to the file rather than returning it.
     * @return string|bool If the filename isn't specified, this function returns a string on success and false on error. If the parameter is specified, it returns true if the file was written successfully and false otherwise.
     */
    public function saveXML(string|null $filename = null): string|bool {}

    /**
     * Runs XPath query on XML data
     * @param string $expression An XPath path
     * @return static[]|false|null an array of SimpleXMLElement objects or FALSE in case of an error.
     */
    public function xpath(string $expression): array|false|null {}

    /**
     * Creates a prefix/ns context for the next XPath query
     * @param string $prefix The namespace prefix to use in the XPath query for the namespace given in ns.
     * @param string $namespace The namespace to use for the XPath query. This must match a namespace in use by the XML document or the XPath query using prefix will not return any results.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function registerXPathNamespace(
        string $prefix,
        string $namespace
    ): bool {}

    /**
     * Identifies an element's attributes
     * @param string $namespaceOrPrefix [optional] An optional namespace for the retrieved attributes
     * @param bool $isPrefix [optional] Default to FALSE
     * @return static|null a SimpleXMLElement object that can be iterated over to loop through the attributes on the tag. Returns NULL if called on a SimpleXMLElement object that already represents an attribute and not a tag.
     * @since 5.0
     */
    public function attributes(
        string|null $namespaceOrPrefix = null,
        bool $isPrefix = false
    ): ?static {}

    /**
     * Finds children of given node
     * @param string $namespaceOrPrefix [optional] An XML namespace.
     * @param bool $isPrefix [optional] If is_prefix is TRUE, ns will be regarded as a prefix. If FALSE, ns will be regarded as a namespace URL.
     * @return static|null a SimpleXMLElement element, whether the node has children or not.
     * @since 5.0
     */
    public function children(
        string|null $namespaceOrPrefix = null,
        bool $isPrefix = false
    ): ?static {}

    /**
     * Returns namespaces used in document
     * @param bool $recursive [optional] If specified, returns all namespaces used in parent and child nodes. Otherwise, returns only namespaces used in root node.
     * @return array The getNamespaces method returns an array of namespace names with their associated URIs.
     * @since 5.1
     */
    public function getNamespaces(bool $recursive = false): array {}

    /**
     * Returns namespaces declared in document
     * @param bool $recursive [optional] If specified, returns all namespaces declared in parent and child nodes. Otherwise, returns only namespaces declared in root node.
     * @param bool $fromRoot [optional] Allows you to recursively check namespaces under a child node instead of from the root of the XML doc.
     * @return array The getDocNamespaces method returns an array of namespace names with their associated URIs.
     * @since 5.1
     */
    public function getDocNamespaces(
        bool $recursive = false,
        bool $fromRoot = true
    ): array|false {}

    /**
     * Gets the name of the XML element
     * @return string The getName method returns as a string the name of the XML tag referenced by the SimpleXMLElement object.
     * @since 5.1
     */
    public function getName(): string {}

    /**
     * Adds a child element to the XML node
     * @param string $qualifiedName The name of the child element to add.
     * @param string $value [optional] If specified, the value of the child element.
     * @param string $namespace [optional] If specified, the namespace to which the child element belongs.
     * @return static|null The addChild method returns a SimpleXMLElement object representing the child added to the XML node.
     * @since 5.1
     */
    public function addChild(
        string $qualifiedName,
        string|null $value = null,
        string|null $namespace = null
    ): ?static {}

    /**
     * Adds an attribute to the SimpleXML element
     * @param string $qualifiedName The name of the attribute to add.
     * @param string $value The value of the attribute.
     * @param string $namespace [optional] If specified, the namespace to which the attribute belongs.
     * @return void No value is returned.
     * @since 5.1
     */
    public function addAttribute(
        string $qualifiedName,
        string $value,
        string|null $namespace = null
    ): void {}

    /**
     * Returns the string content
     * @return string the string content on success or an empty string on failure.
     * @since 5.3
     */
    public function __toString(): string {}

    /**
     * Counts the children of an element
     * @return int<0,max> the number of elements of an element.
     */
    public function count(): int {}

    /**
     * Class provides access to children by position, and attributes by name
     * private Method not callable directly, stub exists for typehint only
     * @param string|int $offset
     * @return bool true on success or false on failure.
     */
    public function offsetExists($offset) {}

    /**
     * Class provides access to children by position, and attributes by name
     * private Method not callable directly, stub exists for typehint only
     * @param string|int $offset
     * @return static Either a named attribute or an element from a list of children
     */
    public function offsetGet($offset) {}

    /**
     * Class provides access to children by position, and attributes by name
     * private Method not callable directly, stub exists for typehint only
     * @param string|int $offset
     * @param mixed $value
     * @return void
     */
    public function offsetSet($offset, $value) {}

    /**
     * Class provides access to children by position, and attributes by name
     * private Method not callable directly, stub exists for typehint only
     * @param string|int $offset
     * @return void
     */
    public function offsetUnset($offset) {}

    /**
     * Rewind to the first element
     * @return void No value is returned.
     */
    public function rewind(): void {}

    /**
     * Check whether the current element is valid
     * @return bool TRUE if the current element is valid, otherwise FALSE
     */
    public function valid(): bool {}

    /**
     * Returns the current element
     * @return static the current element as a SimpleXMLElement object.
     * @throws \Error Throws an Error on failure.
     */
    public function current(): SimpleXMLElement {}

    /**
     * Return current key
     * @return string|false the XML tag name of the element referenced by the current SimpleXMLIterator object
     * @throws \Error Throws an Error on failure.
     */
    public function key(): string {}

    /**
     * Move to next element
     * @return void No value is returned.
     */
    public function next(): void {}

    /**
     * Checks whether the current element has sub elements
     *
     * This method checks whether the current SimpleXMLElement element has sub-elements.
     * @return bool true if the current element has sub-elements, otherwise false
     * @since 8.0
     */
    public function hasChildren(): bool {}

    /**
     * Returns the sub-elements of the current element
     *
     * This method returns a SimpleXMLElement object containing sub-elements of the current
     * SimpleXMLElement element.
     * @since 8.0
     */
    public function getChildren(): ?SimpleXMLElement {}

    /**
     * @since 8.3
     */
    public function __debugInfo(): array|null {}
}
