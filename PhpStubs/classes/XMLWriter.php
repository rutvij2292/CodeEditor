<?php

class XMLWriter
{
    /**
     * Create new xmlwriter using source uri for output
     * @param string $uri The URI of the resource for the output.
     * @return bool Object oriented style: Returns TRUE on success or FALSE on failure. Procedural style: Returns a new xmlwriter resource for later use with the xmlwriter functions on success, FALSE on error.
     */
    public function openUri(string $uri): bool {}

    /**
     * Create new xmlwriter using memory for string output
     * @return bool Object oriented style: Returns TRUE on success or FALSE on failure. Procedural style: Returns a new xmlwriter resource for later use with the xmlwriter functions on success, FALSE on error.
     */
    public function openMemory(): bool {}

    /**
     * Toggle indentation on/off.
     * @param bool|int $enable Whether indentation is enabled or number of indent strings
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setIndent(bool $enable): bool {}

    /**
     * Set string used for indenting.
     * @param string $indentation The indentation string.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setIndentString(string $indentation): bool {}

    /**
     * Create start comment
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startComment(): bool {}

    /**
     * Create end comment
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endComment(): bool {}

    /**
     * Create start attribute
     * @param string $name The attribute name.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startAttribute(string $name): bool {}

    /**
     * End attribute
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endAttribute(): bool {}

    /**
     * Write full attribute
     * @param string $name The name of the attribute.
     * @param string $value The value of the attribute.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeAttribute(
        string $name,
        string $value
    ): bool {}

    /**
     * Create start namespaced attribute
     * @param string|null $prefix The namespace prefix.
     * @param string $name The attribute name.
     * @param string $namespace The namespace URI.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startAttributeNs(
        string|null $prefix,
        string $name,
        string|null $namespace
    ): bool {}

    /**
     * Write full namespaced attribute
     * @param string|null $prefix The namespace prefix.
     * @param string $name The attribute name.
     * @param string $namespace The namespace URI.
     * @param string $value The attribute value.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeAttributeNs(
        string|null $prefix,
        string $name,
        string|null $namespace,
        string $value
    ): bool {}

    /**
     * Create start element tag
     * @param string $name The element name.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startElement(string $name): bool {}

    /**
     * End current element
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endElement(): bool {}

    /**
     * End current element
     * @return bool TRUE on success or FALSE on failure.
     */
    public function fullEndElement(): bool {}

    /**
     * Create start namespaced element tag
     * @param string|null $prefix The namespace prefix.
     * @param string $name The element name.
     * @param string $namespace The namespace URI.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startElementNs(
        string|null $prefix,
        string $name,
        string|null $namespace
    ): bool {}

    /**
     * Write full element tag
     * @param string $name The element name.
     * @param string $content [optional] The element contents.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeElement(
        string $name,
        string|null $content = null
    ): bool {}

    /**
     * Write full namespaced element tag
     * @param string|null $prefix The namespace prefix.
     * @param string $name The element name.
     * @param string $namespace The namespace URI.
     * @param string $content [optional] The element contents.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeElementNs(
        string|null $prefix,
        string $name,
        string|null $namespace,
        string|null $content = null
    ): bool {}

    /**
     * Create start PI tag
     * @param string $target The target of the processing instruction.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startPi(string $target): bool {}

    /**
     * End current PI
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endPi(): bool {}

    /**
     * Writes a PI
     * @param string $target The target of the processing instruction.
     * @param string $content The content of the processing instruction.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writePi(
        string $target,
        string $content
    ): bool {}

    /**
     * Create start CDATA tag
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startCdata(): bool {}

    /**
     * End current CDATA
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endCdata(): bool {}

    /**
     * Write full CDATA tag
     * @param string $content The contents of the CDATA.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeCdata(string $content): bool {}

    /**
     * Write text
     * @param string $content The contents of the text.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function text(string $content): bool {}

    /**
     * Write a raw XML text
     * @param string $content The text string to write.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeRaw(string $content): bool {}

    /**
     * Create document tag
     * @param string $version [optional] The version number of the document as part of the XML declaration.
     * @param string $encoding [optional] The encoding of the document as part of the XML declaration.
     * @param string $standalone [optional] yes or no.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startDocument(
        string|null $version = '1.0',
        string|null $encoding = null,
        string|null $standalone = null
    ): bool {}

    /**
     * End current document
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endDocument(): bool {}

    /**
     * Write full comment tag
     * @param string $content The contents of the comment.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeComment(string $content): bool {}

    /**
     * Create start DTD tag
     * @param string $qualifiedName The qualified name of the document type to create.
     * @param string $publicId [optional] The external subset public identifier.
     * @param string $systemId [optional] The external subset system identifier.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startDtd(
        string $qualifiedName,
        string|null $publicId = null,
        string|null $systemId = null
    ): bool {}

    /**
     * End current DTD
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endDtd(): bool {}

    /**
     * Write full DTD tag
     * @param string $name The DTD name.
     * @param string $publicId [optional] The external subset public identifier.
     * @param string $systemId [optional] The external subset system identifier.
     * @param string $content [optional] The content of the DTD.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeDtd(
        string $name,
        string|null $publicId = null,
        string|null $systemId = null,
        string|null $content = null
    ): bool {}

    /**
     * Create start DTD element
     * @param string $qualifiedName The qualified name of the document type to create.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startDtdElement(string $qualifiedName): bool {}

    /**
     * End current DTD element
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endDtdElement(): bool {}

    /**
     * Write full DTD element tag
     * @param string $name The name of the DTD element.
     * @param string $content The content of the element.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeDtdElement(
        string $name,
        string $content
    ): bool {}

    /**
     * Create start DTD AttList
     * @param string $name The attribute list name.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startDtdAttlist(string $name): bool {}

    /**
     * End current DTD AttList
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endDtdAttlist(): bool {}

    /**
     * Write full DTD AttList tag
     * @param string $name The name of the DTD attribute list.
     * @param string $content The content of the DTD attribute list.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeDtdAttlist(
        string $name,
        string $content
    ): bool {}

    /**
     * Create start DTD Entity
     * @param string $name The name of the entity.
     * @param bool $isParam
     * @return bool TRUE on success or FALSE on failure.
     */
    public function startDtdEntity(
        string $name,
        bool $isParam
    ): bool {}

    /**
     * End current DTD Entity
     * @return bool TRUE on success or FALSE on failure.
     */
    public function endDtdEntity(): bool {}

    /**
     * Write full DTD Entity tag
     * @param string $name The name of the entity.
     * @param string $content The content of the entity.
     * @param bool $isParam
     * @param string|null $publicId
     * @param string|null $systemId
     * @param string|null $notationData
     * @return bool TRUE on success or FALSE on failure.
     */
    public function writeDtdEntity(
        string $name,
        string $content,
        bool $isParam = false,
        string|null $publicId = null,
        string|null $systemId = null,
        string|null $notationData = null
    ): bool {}

    /**
     * Returns current buffer
     * @param bool $flush [optional] Whether to flush the output buffer or not. Default is TRUE.
     * @return string the current buffer as a string.
     */
    public function outputMemory(bool $flush = true): string {}

    /**
     * Flush current buffer
     * @param bool $empty [optional] Whether to empty the buffer or not. Default is TRUE.
     * @return string|int If you opened the writer in memory, this function returns the generated XML buffer, Else, if using URI, this function will write the buffer and return the number of written bytes.
     */
    public function flush(bool $empty = true): string|int {}

    /**
     * Create new XMLWriter using a URI for output
     *
     * Creates a new XMLWriter using a URI for output.
     * @since 8.4
     */
    public static function toUri(string $uri): static {}

    /**
     * Create new XMLWriter using memory for string output
     *
     * Creates a new XMLWriter using memory for string output.
     * @since 8.4
     */
    public static function toMemory(): static {}

    /**
     * Create new XMLWriter using a stream for output
     *
     * Creates a new XMLWriter using a stream for output.
     * @since 8.4
     * @throws \TypeError Passing a resource that is not a stream to stream will throw a TypeError.
     */
    public static function toStream($stream): static {}
}
