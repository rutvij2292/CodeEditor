<?php

/**
 * The DOMNode class
 */
class DOMNode
{
    /**
     * @since 8.4
     */
    public const DOCUMENT_POSITION_DISCONNECTED = 1, DOCUMENT_POSITION_PRECEDING = 2, DOCUMENT_POSITION_FOLLOWING = 4;

    /**
     * @since 8.4
     */
    public const DOCUMENT_POSITION_CONTAINS = 8, DOCUMENT_POSITION_CONTAINED_BY = 16, DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 32;

    /**
     * @var string Returns the most accurate name for the current node type
     */
    public string $nodeName;

    /**
     * @var string|null The value of this node, depending on its type
     */
    public string|null $nodeValue;

    /**
     * @var int Gets the type of the node. One of the predefined XML_xxx_NODE constants
     */
    public int $nodeType;

    /**
     * @var DOMNode|null The parent of this node. If there is no such node, this returns NULL.
     */
    public DOMNode|null $parentNode;

    /**
     * @var DOMNodeList<DOMNode> A DOMNodeList that contains all children of this node. If there are no children, this is an empty DOMNodeList.
     */
    public DOMNodeList $childNodes;

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
     * @var DOMNamedNodeMap<DOMAttr>|null A DOMNamedNodeMap containing the attributes of this node (if it is a DOMElement) or NULL otherwise.
     */
    public DOMNamedNodeMap|null $attributes;

    /**
     * @var DOMDocument|null The DOMDocument object associated with this node, or NULL if this node is a DOMDocument.
     */
    public DOMDocument|null $ownerDocument;

    /**
     * @var string|null The namespace URI of this node, or NULL if it is unspecified.
     */
    public string|null $namespaceURI;

    /**
     * @var string|null The namespace prefix of this node, or NULL if it is unspecified.
     */
    public string $prefix;

    /**
     * @var string|null Returns the local part of the qualified name of this node.
     */
    public string|null $localName;

    /**
     * @var string|null The absolute base URI of this node or NULL if the implementation wasn't able to obtain an absolute URI.
     */
    public string|null $baseURI;

    /**
     * @var string This attribute returns the text content of this node and its descendants.
     */
    public string $textContent;

    public bool $isConnected;

    public ?DOMElement $parentElement;

    /**
     * Adds a new child before a reference node
     * @template TNode of DOMNode
     * @param TNode $node The new node.
     * @param null|DOMNode $child [optional] The reference node. If not supplied, newnode is appended to the children.
     * @return TNode|false The inserted node.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if this node is readonly or if the previous parent of the node being inserted is readonly. DOM_HIERARCHY_REQUEST_ERR Raised if this node is of a type that does not allow children of ...
     */
    public function insertBefore(
        DOMNode $node,
        DOMNode|null $child = null
    ) {}

    /**
     * Replaces a child
     * @template TNode of DOMNode
     * @param DOMNode $node The new node. It must be a member of the target document, i.e. created by one of the DOMDocument->createXXX() methods or imported in the document by .
     * @param TNode $child The old node.
     * @return TNode|false The old node or false if an error occur.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if this node is readonly or if the previous parent of the node being inserted is readonly. DOM_HIERARCHY_REQUEST_ERR Raised if this node is of a type that does not allow children of ...
     */
    public function replaceChild(DOMNode $node, DOMNode $child) {}

    /**
     * Removes child from list of children
     * @template TNode of DOMNode
     * @param TNode $child The removed child.
     * @return TNode|false If the child could be removed the functions returns the old child.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if this node is readonly. DOM_NOT_FOUND_ERR Raised if child is not a child of this node.
     */
    public function removeChild(DOMNode $child) {}

    /**
     * Adds new child at the end of the children
     * @template TNode of DOMNode
     * @param TNode $node The appended child.
     * @return TNode|false The node added.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_NO_MODIFICATION_ALLOWED_ERR Raised if this node is readonly or if the previous parent of the node being inserted is readonly. DOM_HIERARCHY_REQUEST_ERR Raised if this node is of a type that does not allow children of ...
     */
    public function appendChild(DOMNode $node) {}

    /**
     * Checks if node has children
     * @return bool true on success or false on failure.
     */
    public function hasChildNodes(): bool {}

    /**
     * Clones a node
     * @param bool $deep Indicates whether to copy all descendant nodes. This parameter is defaulted to false.
     * @return static|false The cloned node.
     */
    public function cloneNode(
        bool $deep = false
    ) {}

    /**
     * Normalizes the node
     * @return void No value is returned.
     */
    public function normalize(): void {}

    /**
     * Checks if feature is supported for specified version
     * @param string $feature The feature to test. See the example of DOMImplementation::hasFeature for a list of features.
     * @param string $version The version number of the feature to test.
     * @return bool true on success or false on failure.
     */
    public function isSupported(
        string $feature,
        string $version
    ): bool {}

    /**
     * Checks if node has attributes
     * @return bool true on success or false on failure.
     */
    public function hasAttributes(): bool {}

    /**
     * Compares the position of two nodes
     *
     * Compares the position of the other node relative to this node.
     * @return int A bitmask of the DOMNode::DOCUMENT_POSITION_* constants.
     */
    public function compareDocumentPosition(DOMNode $other) {}

    /**
     * Indicates if two nodes are the same node
     * @param DOMNode $otherNode The compared node.
     * @return bool true on success or false on failure.
     */
    public function isSameNode(DOMNode $otherNode): bool {}

    /**
     * Gets the namespace prefix of the node based on the namespace URI
     * @param string $namespace The namespace URI.
     * @return string The prefix of the namespace.
     */
    public function lookupPrefix(string $namespace): ?string {}

    /**
     * Checks if the specified namespaceURI is the default namespace or not
     * @param string $namespace The namespace URI to look for.
     * @return bool Return true if namespaceURI is the default namespace, false otherwise.
     */
    public function isDefaultNamespace(string $namespace): bool {}

    /**
     * Gets the namespace URI of the node based on the prefix
     * @param string|null $prefix The prefix of the namespace.
     * @return string|null The namespace URI of the node.
     */
    public function lookupNamespaceURI(?string $prefix): ?string {}

    /**
     * Checks that both nodes are equal
     * @param DOMNode|null $otherNode The node.
     * @return bool Returns true if both nodes are equal, false otherwise.
     */
    public function isEqualNode(DOMNode|null $otherNode): bool {}

    /**
     * @removed 8.0
     */
    public function getFeature($feature, $version) {}

    /**
     * @removed 8.0
     */
    public function setUserData($key, $data, $handler) {}

    /**
     * @removed 8.0
     */
    public function getUserData($key) {}

    /**
     * Gets an XPath location path for the node
     * @return string|null the XPath, or NULL in case of an error.
     */
    public function getNodePath(): ?string {}

    /**
     * Get line number for a node
     * @return int Always returns the line number where the node was defined in.
     */
    public function getLineNo(): int {}

    /**
     * Canonicalize nodes to a string
     * @param bool $exclusive [optional] Enable exclusive parsing of only the nodes matched by the provided xpath or namespace prefixes.
     * @param bool $withComments [optional] Retain comments in output.
     * @param null|array $xpath [optional] An array of xpaths to filter the nodes by.
     * @param null|array $nsPrefixes [optional] An array of namespace prefixes to filter the nodes by.
     * @return string|false Canonicalized nodes as a string or FALSE on failure
     */
    public function C14N(
        bool $exclusive = false,
        bool $withComments = false,
        array|null $xpath = null,
        array|null $nsPrefixes = null
    ): string|false {}

    /**
     * Canonicalize nodes to a file.
     * @param string $uri Path to write the output to.
     * @param bool $exclusive [optional] Enable exclusive parsing of only the nodes matched by the provided xpath or namespace prefixes.
     * @param bool $withComments [optional]  Retain comments in output.
     * @param null|array $xpath [optional] An array of xpaths to filter the nodes by.
     * @param null|array $nsPrefixes [optional] An array of namespace prefixes to filter the nodes by.
     * @return int|false Number of bytes written or FALSE on failure
     */
    public function C14NFile(
        string $uri,
        bool $exclusive = false,
        bool $withComments = false,
        array|null $xpath = null,
        array|null $nsPrefixes = null
    ): int|false {}

    /**
     * Checks if node contains other node
     * @since 8.3
     */
    public function contains(DOMNode|DOMNameSpaceNode|null $other): bool {}

    /**
     * Get root node
     * @since 8.3
     */
    public function getRootNode(?array $options = null): DOMNode {}

    /**
     * Forbids serialization unless serialization methods are implemented in a subclass
     * @since 8.1
     * @throws \Error Throws an Error exception when called.
     */
    public function __sleep(): array {}

    /**
     * Forbids unserialization unless unserialization methods are implemented in a subclass
     * @since 8.1
     * @throws \Error Throws an Error exception when called.
     */
    public function __wakeup(): void {}
}
