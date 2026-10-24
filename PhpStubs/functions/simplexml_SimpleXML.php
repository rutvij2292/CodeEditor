<?php

/**
 * Interprets an XML file into an object
 * @param string $filename Path to the XML file Libxml 2 unescapes the URI, so if you want to pass e.g. b&c as the URI parameter a, you have to call simplexml_load_file(rawurlencode('https://example.com/?a=' . urlencode('b&c'))). Since PHP 5.1.0 you don't need to do this because PHP will do it for you.
 * @param string|null $class_name [optional] You may use this optional parameter so that simplexml_load_file will return an object of the specified class. That class should extend the SimpleXMLElement class.
 * @param int $options [optional] Since PHP 5.1.0 and Libxml 2.6.0, you may also use the options parameter to specify additional Libxml parameters.
 * @param string $namespace_or_prefix [optional] Namespace prefix or URI.
 * @param bool $is_prefix [optional] TRUE if ns is a prefix, FALSE if it's a URI; defaults to FALSE.
 * @return SimpleXMLElement|false an object of class SimpleXMLElement with properties containing the data held within the XML document, or FALSE on failure.
 */
function simplexml_load_file(string $filename, ?string $class_name = "SimpleXMLElement", int $options = 0, string $namespace_or_prefix = "", bool $is_prefix = false): SimpleXMLElement|false {}

/**
 * Interprets a string of XML into an object
 * @param string $data A well-formed XML string
 * @param string|null $class_name [optional] You may use this optional parameter so that simplexml_load_string will return an object of the specified class. That class should extend the SimpleXMLElement class.
 * @param int $options [optional] Since PHP 5.1.0 and Libxml 2.6.0, you may also use the options parameter to specify additional Libxml parameters.
 * @param string $namespace_or_prefix [optional] Namespace prefix or URI.
 * @param bool $is_prefix [optional] TRUE if ns is a prefix, FALSE if it's a URI; defaults to FALSE.
 * @return SimpleXMLElement|false an object of class SimpleXMLElement with properties containing the data held within the xml document, or FALSE on failure.
 */
function simplexml_load_string(string $data, ?string $class_name = "SimpleXMLElement", int $options = 0, string $namespace_or_prefix = "", bool $is_prefix = false): SimpleXMLElement|false {}

/**
 * Get a SimpleXMLElement object from a DOM node.
 * @param SimpleXMLElement|DOMNode $node A DOM Element node
 * @param string|null $class_name [optional] You may use this optional parameter so that simplexml_import_dom will return an object of the specified class. That class should extend the SimpleXMLElement class.
 * @return SimpleXMLElement|null a SimpleXMLElement, or NULL on failure. Prior to PHP 8.0, FALSE was returned instead of NULL.
 * @throws \TypeError Throws a TypeError when passed a non-XML or non-HTML node.
 */
function simplexml_import_dom(SimpleXMLElement|DOMNode $node, ?string $class_name = "SimpleXMLElement"): ?SimpleXMLElement {}
