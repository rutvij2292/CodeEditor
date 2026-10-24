<?php
namespace Dom;

/**
 * Represents an HTML document.
 * @since 8.4
 */
final class HTMLDocument extends Document
{
    /**
     * Creates an empty HTML document
     *
     * Creates an empty HTML document without any elements.
     * @param string $encoding The character encoding of the document, used for serialization when calling the save methods.
     * @return HTMLDocument An empty HTML document.
     */
    public static function createEmpty(string $encoding = "UTF-8"): HTMLDocument {}

    /**
     * Parses an HTML document from a file
     *
     * Parses an HTML document from a file, according to the living standard.
     * @param string $path The path to the file to parse.
     * @param int $options Bitwise OR of the libxml option constants. It is also possible to pass Dom\HTML_NO_DEFAULT_NS to disable the use of the HTML namespace and the template element. This should only be used if the implications are properly understood.
     * @param string|null $overrideEncoding The encoding that the document was created in. If not provided, it will attempt to determine the encoding that is most likely used.
     * @return HTMLDocument The parsed document as an Dom\HTMLDocument instance.
     * @throws \ValueError Throws a ValueError if path contains null bytes or contains "%00". Throws a ValueError if options contains an invalid option. Throws a ValueError if overrideEncoding is an unknown encoding.
     * @throws \Exception Throws an Exception if the file could not be opened.
     */
    public static function createFromFile(string $path, int $options = 0, ?string $overrideEncoding = null): HTMLDocument {}

    /**
     * Parses an HTML document from a string
     *
     * Parses an HTML document from a string, according to the living standard.
     * @param string $source The string containing the HTML to parse.
     * @param int $options Bitwise OR of the libxml option constants. It is also possible to pass Dom\HTML_NO_DEFAULT_NS to disable the use of the HTML namespace and the template element. This should only be used if the implications are properly understood.
     * @param string|null $overrideEncoding The encoding that the document was created in. If not provided, it will attempt to determine the encoding that is most likely used.
     * @return HTMLDocument The parsed document as an Dom\HTMLDocument instance.
     * @throws \ValueError Throws a ValueError if options contains an invalid option. Throws a ValueError if overrideEncoding is an unknown encoding.
     */
    public static function createFromString(string $source, int $options = 0, ?string $overrideEncoding = null): HTMLDocument {}

    /**
     * Serializes the document as an XML string
     * @param Node|null $node The node to serialize. If not provided, the entire document is serialized.
     * @param int $options Additional Options. The LIBXML_NOEMPTYTAG and LIBXML_NOXMLDECL options are supported. Prior to PHP 8.3.0, only the LIBXML_NOEMPTYTAG option is supported.
     * @return string|false The serialized XML document string in the current document encoding, or false on failure.
     */
    public function saveXml(?Node $node = null, int $options = 0): string|false {}

    /**
     * Serializes the document as an XML file
     * @param string $filename The path to the file to save to.
     * @param int $options Additional Options. The LIBXML_NOEMPTYTAG and LIBXML_NOXMLDECL options are supported. Prior to PHP 8.3.0, only the LIBXML_NOEMPTYTAG option is supported.
     * @return int|false The number of bytes written on success, or false on failure.
     * @throws \ValueError Throws a ValueError if filename is an empty string or contains any null bytes.
     */
    public function saveXmlFile(string $filename, int $options = 0): int|false {}

    /**
     * Serializes the document as an HTML string
     * @param Node|null $node The node to serialize. If not provided, the entire document is serialized.
     * @return string The serialized HTML document string in the current document encoding.
     */
    public function saveHtml(?Node $node = null): string {}

    /**
     * Serializes the document as an HTML file
     * @param string $filename The path to the file to save to.
     * @return int|false The number of bytes written on success, or false on failure.
     * @throws \ValueError Throws a ValueError if filename is an empty string or contains any null bytes.
     */
    public function saveHtmlFile(string $filename): int|false {}
}
