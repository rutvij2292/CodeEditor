<?php

/**
 * Create new xmlwriter using source uri for output
 * @param string $uri The URI of the resource for the output.
 * @return false|resource|XMLWriter Object oriented style: Returns TRUE on success or FALSE on failure. Procedural style: Returns a new xmlwriter resource for later use with the xmlwriter functions on success, FALSE on error.
 */
function xmlwriter_open_uri(string $uri): XMLWriter|false {}

/**
 * Create new xmlwriter using memory for string output
 * @return XMLWriter|false|resource Object oriented style: Returns TRUE on success or FALSE on failure. Procedural style: Returns a new xmlwriter resource for later use with the xmlwriter functions on success, FALSE on error.
 */
function xmlwriter_open_memory(): XMLWriter|false {}

/**
 * Toggle indentation on/off
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param bool $enable Whether indentation is enabled.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_set_indent(XMLWriter $writer, bool $enable): bool {}

/**
 * Set string used for indenting
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $indentation The indentation string.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_set_indent_string(XMLWriter $writer, string $indentation): bool {}

/**
 * Create start comment
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_comment(XMLWriter $writer): bool {}

/**
 * Create end comment
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_comment(XMLWriter $writer): bool {}

/**
 * Create start attribute
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The attribute name.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_attribute(XMLWriter $writer, string $name): bool {}

/**
 * End attribute
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_attribute(XMLWriter $writer): bool {}

/**
 * Write full attribute
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The name of the attribute.
 * @param string $value The value of the attribute.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_attribute(XMLWriter $writer, string $name, string $value): bool {}

/**
 * Create start namespaced attribute
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string|null $prefix The namespace prefix.
 * @param string $name The attribute name.
 * @param string|null $namespace The namespace URI.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_attribute_ns(XMLWriter $writer, ?string $prefix, string $name, ?string $namespace): bool {}

/**
 * Write full namespaced attribute
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string|null $prefix The namespace prefix.
 * @param string $name The attribute name.
 * @param string|null $namespace The namespace URI.
 * @param string $value The attribute value.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_attribute_ns(XMLWriter $writer, ?string $prefix, string $name, ?string $namespace, string $value): bool {}

/**
 * Create start element tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The element name.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_element(XMLWriter $writer, string $name): bool {}

/**
 * End current element
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_element(XMLWriter $writer): bool {}

/**
 * End current element
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_full_end_element(XMLWriter $writer): bool {}

/**
 * Create start namespaced element tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string|null $prefix The namespace prefix.
 * @param string $name The element name.
 * @param string|null $namespace The namespace URI.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_element_ns(XMLWriter $writer, ?string $prefix, string $name, ?string $namespace): bool {}

/**
 * Write full element tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The element name.
 * @param string|null $content [optional] The element contents.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_element(XMLWriter $writer, string $name, ?string $content = null): bool {}

/**
 * Write full namespaced element tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string|null $prefix The namespace prefix.
 * @param string $name The element name.
 * @param string|null $namespace The namespace URI.
 * @param string|null $content [optional] The element contents.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_element_ns(XMLWriter $writer, ?string $prefix, string $name, ?string $namespace, ?string $content = null): bool {}

/**
 * Create start PI tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $target The target of the processing instruction.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_pi(XMLWriter $writer, string $target): bool {}

/**
 * End current PI
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_pi(XMLWriter $writer): bool {}

/**
 * Writes a PI
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $target The target of the processing instruction.
 * @param string $content The content of the processing instruction.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_pi(XMLWriter $writer, string $target, string $content): bool {}

/**
 * Create start CDATA tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_cdata(XMLWriter $writer): bool {}

/**
 * End current CDATA
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_cdata(XMLWriter $writer): bool {}

/**
 * Write full CDATA tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $content The contents of the CDATA.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_cdata(XMLWriter $writer, string $content): bool {}

/**
 * Write text
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $content The contents of the text.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_text(XMLWriter $writer, string $content): bool {}

/**
 * Write a raw XML text
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $content The text string to write.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_raw(XMLWriter $writer, string $content): bool {}

/**
 * Create document tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string|null $version [optional] The version number of the document as part of the XML declaration.
 * @param string|null $encoding [optional] The encoding of the document as part of the XML declaration.
 * @param string|null $standalone [optional] yes or no.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_document(XMLWriter $writer, ?string $version = '1.0', ?string $encoding = null, ?string $standalone = null): bool {}

/**
 * End current document
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_document(XMLWriter $writer): bool {}

/**
 * Write full comment tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $content The contents of the comment.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_comment(XMLWriter $writer, string $content): bool {}

/**
 * Create start DTD tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $qualifiedName The qualified name of the document type to create.
 * @param string|null $publicId [optional] The external subset public identifier.
 * @param string|null $systemId [optional] The external subset system identifier.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_dtd(XMLWriter $writer, string $qualifiedName, ?string $publicId = null, ?string $systemId = null): bool {}

/**
 * End current DTD
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_dtd(XMLWriter $writer): bool {}

/**
 * Write full DTD tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The DTD name.
 * @param string|null $publicId [optional] The external subset public identifier.
 * @param string|null $systemId [optional] The external subset system identifier.
 * @param string|null $content [optional] The content of the DTD.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_dtd(XMLWriter $writer, string $name, ?string $publicId = null, ?string $systemId = null, ?string $content = null): bool {}

/**
 * Create start DTD element
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $qualifiedName The qualified name of the document type to create.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_dtd_element(XMLWriter $writer, string $qualifiedName): bool {}

/**
 * End current DTD element
 * @param $writer Only for procedural calls. The XMLWriter instance that is being modified. This object is returned from a call to xmlwriter_open_uri or xmlwriter_open_memory.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_dtd_element(XMLWriter $writer): bool {}

/**
 * Write full DTD element tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The name of the DTD element.
 * @param string $content The content of the element.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_dtd_element(XMLWriter $writer, string $name, string $content): bool {}

/**
 * Create start DTD AttList
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The attribute list name.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_dtd_attlist(XMLWriter $writer, string $name): bool {}

/**
 * End current DTD AttList
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_dtd_attlist(XMLWriter $writer): bool {}

/**
 * Write full DTD AttList tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The name of the DTD attribute list.
 * @param string $content The content of the DTD attribute list.
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_dtd_attlist(XMLWriter $writer, string $name, string $content): bool {}

/**
 * Create start DTD Entity
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The name of the entity.
 * @param bool $isParam
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_start_dtd_entity(XMLWriter $writer, string $name, bool $isParam): bool {}

/**
 * End current DTD Entity
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory(). * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_end_dtd_entity(XMLWriter $writer): bool {}

/**
 * Write full DTD Entity tag
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param string $name The name of the entity.
 * @param string $content The content of the entity.
 * @param bool $isParam
 * @param string $publicId
 * @param string $systemId
 * @param string $notationData
 * @return bool TRUE on success or FALSE on failure.
 */
function xmlwriter_write_dtd_entity(
    XMLWriter $writer,
    string $name,
    string $content,
    bool $isParam = false,
    ?string $publicId = null,
    ?string $systemId = null,
    ?string $notationData = null
): bool {}

/**
 * Returns current buffer
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param bool $flush [optional] Whether to flush the output buffer or not. Default is TRUE.
 * @return string the current buffer as a string.
 */
function xmlwriter_output_memory(XMLWriter $writer, bool $flush = true): string {}

/**
 * Flush current buffer
 * @param resource|XMLWriter $writer Only for procedural calls. The XMLWriter resource that is being modified. This resource comes from a call to xmlwriter_open_uri() or xmlwriter_open_memory().
 * @param bool $empty [optional] Whether to empty the buffer or not. Default is TRUE.
 * @return string|int If you opened the writer in memory, this function returns the generated XML buffer, Else, if using URI, this function will write the buffer and return the number of written bytes.
 */
function xmlwriter_flush(XMLWriter $writer, bool $empty = true): string|int {}
