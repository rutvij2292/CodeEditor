<?php

/**
 * The DOMElement class
 */
class DOMElement extends DOMNode implements DOMParentNode, DOMChildNode
{
    /**
     * @var DOMNode|null The parent of this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $parentNode;

    /**
     * @var DOMNode|null The first child of this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $firstChild;

    /**
     * @var DOMNode|null The last child of this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $lastChild;

    /**
     * @var DOMNode|null The node immediately preceding this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $previousSibling;

    /**
     * @var DOMNode|null The node immediately following this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $nextSibling;

    /**
     * @var DOMNamedNodeMap<DOMAttr> A DOMNamedNodeMap containing the attributes of this node (if it is a DOMElement) or NULL otherwise.
     */
    public DOMNamedNodeMap|null $attributes;

    /**
     * @var bool Not implemented yet, always return NULL
     */
    public mixed $schemaTypeInfo;

    /**
     * @var string The element name
     */
    public string $tagName;

    public DOMElement|null $firstElementChild;

    public DOMElement|null $lastElementChild;

    public int $childElementCount;

    public DOMElement|null $previousElementSibling;

    public DOMElement|null $nextElementSibling;

    public string $id;

    public string $className;

    /**
     * Returns value of attribute
     * @param string $qualifiedName The name of the attribute.
     * @return string The value of the attribute, or an empty string if no attribute with the given name is found.
     */
    public function getAttribute(string $qualifiedName): string {}

    /**
     * Adds new attribute
     * @param string $qualifiedName The name of the attribute.
     * @param string $value The value of the attribute.
     * @return DOMAttr|false The new DOMAttr or false if an error occurred.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly.
     */
    public function setAttribute(
        string $qualifiedName,
        string $value
    ) {}

    /**
     * Removes attribute
     * @param string $qualifiedName The name of the attribute.
     * @return bool true on success or false on failure.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly.
     */
    public function removeAttribute(string $qualifiedName): bool {}

    /**
     * Returns attribute node
     * @param string $qualifiedName The name of the attribute.
     * @return DOMAttr|false The attribute node or false if there is none.
     */
    public function getAttributeNode(string $qualifiedName) {}

    /**
     * Adds new attribute node to element
     * @param DOMAttr $attr The attribute node.
     * @return DOMAttr|null Old node if the attribute has been replaced or null.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_WRONG_DOCUMENT_ERR Raised if attr belongs to a different document than the element.
     */
    public function setAttributeNode(DOMAttr $attr) {}

    /**
     * Removes attribute
     * @param DOMAttr $attr The attribute node.
     * @return bool true on success or false on failure.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly. DOM_NOT_FOUND_ERR Raised if attr is not an attribute of the element.
     */
    public function removeAttributeNode(DOMAttr $attr) {}

    /**
     * Gets elements by tagname
     * @param string $qualifiedName The tag name. Use * to return all elements within the element tree.
     * @return DOMNodeList<DOMElement> This function returns a new instance of the class DOMNodeList of all matched elements.
     */
    public function getElementsByTagName(string $qualifiedName): DOMNodeList {}

    /**
     * Returns value of attribute
     * @param string $namespace The namespace URI.
     * @param string $localName The local name.
     * @return string The value of the attribute, or an empty string if no attribute with the given localName and namespaceURI is found.
     */
    public function getAttributeNS(
        string|null $namespace,
        string $localName
    ): string {}

    /**
     * Adds new attribute
     * @param string $namespace The namespace URI.
     * @param string $qualifiedName The qualified name of the attribute, as prefix:tagname.
     * @param string $value The value of the attribute.
     * @return void No value is returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly. DOM_NAMESPACE_ERR Raised if qualifiedName is a malformed qualified name, or if qualifiedName has a prefix and namespace is null.
     */
    public function setAttributeNS(
        string|null $namespace,
        string $qualifiedName,
        string $value
    ): void {}

    /**
     * Removes attribute
     * @param string $namespace The namespace URI.
     * @param string $localName The local name.
     * @return void No value is returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly.
     */
    public function removeAttributeNS(
        string|null $namespace,
        string $localName
    ): void {}

    /**
     * Returns attribute node
     * @param string $namespace The namespace URI.
     * @param string $localName The local name.
     * @return DOMAttr|null The attribute node.
     */
    public function getAttributeNodeNS(
        string|null $namespace,
        string $localName
    ) {}

    /**
     * Adds new attribute node to element
     * @param DOMAttr $attr The attribute node.
     * @return DOMAttr the old node if the attribute has been replaced.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_WRONG_DOCUMENT_ERR Raised if attr belongs to a different document than the element.
     */
    public function setAttributeNodeNS(DOMAttr $attr) {}

    /**
     * Get elements by namespaceURI and localName
     * @param string $namespace The namespace URI.
     * @param string $localName The local name. Use * to return all elements within the element tree.
     * @return DOMNodeList<DOMElement> This function returns a new instance of the class DOMNodeList of all matched elements in the order in which they are encountered in a preorder traversal of this element tree.
     */
    public function getElementsByTagNameNS(
        string|null $namespace,
        string $localName
    ): DOMNodeList {}

    /**
     * Checks to see if attribute exists
     * @param string $qualifiedName The attribute name.
     * @return bool true on success or false on failure.
     */
    public function hasAttribute(string $qualifiedName): bool {}

    /**
     * Checks to see if attribute exists
     * @param string $namespace The namespace URI.
     * @param string $localName The local name.
     * @return bool true on success or false on failure.
     */
    public function hasAttributeNS(
        string|null $namespace,
        string $localName
    ): bool {}

    /**
     * Declares the attribute specified by name to be of type ID
     * @param string $qualifiedName The name of the attribute.
     * @param bool $isId Set it to true if you want name to be of type ID, false otherwise.
     * @return void No value is returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly. DOM_NOT_FOUND_ERR Raised if qualifiedName is not an attribute of this element.
     */
    public function setIdAttribute(
        string $qualifiedName,
        bool $isId
    ): void {}

    /**
     * Declares the attribute specified by local name and namespace URI to be of type ID
     * @param string $namespace The namespace URI of the attribute.
     * @param string $qualifiedName The local name of the attribute, as prefix:tagname.
     * @param bool $isId Set it to true if you want name to be of type ID, false otherwise.
     * @return void No value is returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly. DOM_NOT_FOUND_ERR Raised if name is not an attribute of this element.
     */
    public function setIdAttributeNS(
        string $namespace,
        string $qualifiedName,
        bool $isId
    ): void {}

    /**
     * Declares the attribute specified by node to be of type ID
     * @param DOMAttr $attr The attribute node.
     * @param bool $isId Set it to true if you want name to be of type ID, false otherwise.
     * @return void No value is returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if the node is readonly. DOM_NOT_FOUND_ERR Raised if name is not an attribute of this element.
     */
    public function setIdAttributeNode(DOMAttr $attr, bool $isId): void {}

    /**
     * {@inheritDoc}
     */
    public function remove(): void {}

    /**
     * {@inheritDoc}
     */
    public function before(...$nodes): void {}

    /**
     * {@inheritDoc}
     */
    public function after(...$nodes): void {}

    /**
     * {@inheritDoc}
     */
    public function replaceWith(...$nodes): void {}

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
     * Creates a new DOMElement object
     * @param string $qualifiedName The tag name of the element. When also passing in namespaceURI, the element name may take a prefix to be associated with the URI.
     * @param string|null $value [optional] The value of the element.
     * @param string $namespace [optional] A namespace URI to create the element within a specific namespace.
     * @throws DOMException If invalid $qualifiedName
     */
    public function __construct(
        string $qualifiedName,
        string|null $value = null,
        string $namespace = ''
    ) {}

    /**
     * Get attribute names
     * @since 8.3
     */
    public function getAttributeNames(): array {}

    /**
     * Toggle attribute
     *
     * Toggle the attribute.
     * @since 8.3
     */
    public function toggleAttribute(string $qualifiedName, ?bool $force = null): bool {}

    /**
     * Insert adjacent element
     *
     * Inserts an element at a relative position given by where.
     * @since 8.3
     */
    public function insertAdjacentElement(string $where, DOMElement $element): ?DOMElement {}

    /**
     * Insert adjacent text
     *
     * Inserts text at a relative position given by where.
     * @since 8.3
     */
    public function insertAdjacentText(string $where, string $data): void {}
}
