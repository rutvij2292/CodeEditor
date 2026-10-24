<?php

/**
 * Node is a DOMElement
 */
const XML_ELEMENT_NODE = 1;

/**
 * Node is a DOMAttr
 */
const XML_ATTRIBUTE_NODE = 2;

/**
 * Node is a DOMText
 */
const XML_TEXT_NODE = 3;

/**
 * Node is a DOMCharacterData
 */
const XML_CDATA_SECTION_NODE = 4;

/**
 * Node is a DOMEntityReference
 */
const XML_ENTITY_REF_NODE = 5;

/**
 * Node is a DOMEntity
 */
const XML_ENTITY_NODE = 6;

/**
 * Node is a DOMProcessingInstruction
 */
const XML_PI_NODE = 7;

/**
 * Node is a DOMComment
 */
const XML_COMMENT_NODE = 8;

/**
 * Node is a DOMDocument
 */
const XML_DOCUMENT_NODE = 9;

/**
 * Node is a DOMDocumentType
 */
const XML_DOCUMENT_TYPE_NODE = 10;

/**
 * Node is a DOMDocumentFragment
 */
const XML_DOCUMENT_FRAG_NODE = 11;

/**
 * Node is a DOMNotation
 */
const XML_NOTATION_NODE = 12;

const XML_HTML_DOCUMENT_NODE = 13;

const XML_DTD_NODE = 14;

const XML_ELEMENT_DECL_NODE = 15;

const XML_ATTRIBUTE_DECL_NODE = 16;

const XML_ENTITY_DECL_NODE = 17;

const XML_NAMESPACE_DECL_NODE = 18;

const XML_LOCAL_NAMESPACE = 18;

const XML_ATTRIBUTE_CDATA = 1;

const XML_ATTRIBUTE_ID = 2;

const XML_ATTRIBUTE_IDREF = 3;

const XML_ATTRIBUTE_IDREFS = 4;

const XML_ATTRIBUTE_ENTITY = 6;

const XML_ATTRIBUTE_NMTOKEN = 7;

const XML_ATTRIBUTE_NMTOKENS = 8;

const XML_ATTRIBUTE_ENUMERATION = 9;

const XML_ATTRIBUTE_NOTATION = 10;

/**
 * Error code not part of the DOM specification. Meant for PHP errors.
 * @deprecated 8.4
 */
const DOM_PHP_ERR = 0;

/**
 * If index or size is negative, or greater than the allowed value.
 */
const DOM_INDEX_SIZE_ERR = 1;

/**
 * If the specified range of text does not fit into a
 * DOMString.
 */
const DOMSTRING_SIZE_ERR = 2;

/**
 * If any node is inserted somewhere it doesn't belong
 */
const DOM_HIERARCHY_REQUEST_ERR = 3;

/**
 * If a node is used in a different document than the one that created it.
 */
const DOM_WRONG_DOCUMENT_ERR = 4;

/**
 * If an invalid or illegal character is specified, such as in a name.
 */
const DOM_INVALID_CHARACTER_ERR = 5;

/**
 * If data is specified for a node which does not support data.
 */
const DOM_NO_DATA_ALLOWED_ERR = 6;

/**
 * If an attempt is made to modify an object where modifications are not allowed.
 */
const DOM_NO_MODIFICATION_ALLOWED_ERR = 7;

/**
 * If an attempt is made to reference a node in a context where it does not exist.
 */
const DOM_NOT_FOUND_ERR = 8;

/**
 * If the implementation does not support the requested type of object or operation.
 */
const DOM_NOT_SUPPORTED_ERR = 9;

/**
 * If an attempt is made to add an attribute that is already in use elsewhere.
 */
const DOM_INUSE_ATTRIBUTE_ERR = 10;

/**
 * If an attempt is made to use an object that is not, or is no longer, usable.
 */
const DOM_INVALID_STATE_ERR = 11;

/**
 * If an invalid or illegal string is specified.
 */
const DOM_SYNTAX_ERR = 12;

/**
 * If an attempt is made to modify the type of the underlying object.
 */
const DOM_INVALID_MODIFICATION_ERR = 13;

/**
 * If an attempt is made to create or change an object in a way which is
 * incorrect with regard to namespaces.
 */
const DOM_NAMESPACE_ERR = 14;

/**
 * If a parameter or an operation is not supported by the underlying object.
 */
const DOM_INVALID_ACCESS_ERR = 15;

/**
 * If a call to a method such as insertBefore or removeChild would make the Node
 * invalid with respect to "partial validity", this exception would be raised and
 * the operation would not be done.
 */
const DOM_VALIDATION_ERR = 16;
