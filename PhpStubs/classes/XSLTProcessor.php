<?php

class XSLTProcessor
{
    /**
     * Import stylesheet
     * @param object $stylesheet The imported style sheet as a DOMDocument or SimpleXMLElement object.
     * @return bool TRUE on success or FALSE on failure.
     * @throws \TypeError Throws a TypeError if stylesheet is not an XML object.
     */
    public function importStylesheet(object $stylesheet): bool {}

    /**
     * Transform to a DOMDocument
     * @param object $document The DOMDocument or SimpleXMLElement or libxml-compatible object to be transformed.
     * @param string|null $returnClass This optional parameter may be used so that XSLTProcessor::transformToDoc will return an object of the specified class. That class should either extend or be the same class as document's class.
     * @return DOMDocument|false The resulting DOMDocument or FALSE on error.
     */
    public function transformToDoc(
        object $document,
        string|null $returnClass = null
    ): object|false {}

    /**
     * Transform to URI
     * @param DOMDocument|SimpleXMLElement $document The document to transform.
     * @param string $uri The target URI for the transformation.
     * @return int the number of bytes written or FALSE if an error occurred.
     */
    public function transformToUri(
        object $document,
        string $uri
    ): int {}

    /**
     * Transform to XML
     * @param DOMDocument|SimpleXMLElement $document The transformed document.
     * @return string|false|null The result of the transformation as a string or FALSE on error.
     */
    public function transformToXml(object $document): string|false|null {}

    /**
     * Set value for a parameter
     * @param string $namespace The namespace URI of the XSLT parameter.
     * @param string $name The local name of the XSLT parameter.
     * @param string $value The new value of the XSLT parameter.
     * @return bool TRUE on success or FALSE on failure.
     * @throws \ValueError Throws a ValueError if any of the arguments contain null bytes.
     */
    public function setParameter(
        string $namespace,
        array|string $name,
        string|null $value = null
    ): bool {}

    /**
     * Get value of a parameter
     * @param string $namespace The namespace URI of the XSLT parameter.
     * @param string $name The local name of the XSLT parameter.
     * @return string|false The value of the parameter (as a string), or FALSE if it's not set.
     */
    public function getParameter(
        string $namespace,
        string $name
    ): string|false {}

    /**
     * Remove parameter
     * @param string $namespace The namespace URI of the XSLT parameter.
     * @param string $name The local name of the XSLT parameter.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function removeParameter(
        string $namespace,
        string $name
    ): bool {}

    /**
     * Determine if PHP has EXSLT support
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.0
     */
    public function hasExsltSupport(): bool {}

    /**
     * Enables the ability to use PHP functions as XSLT functions
     * @param array|string|null $functions [optional] Use this parameter to only allow certain functions to be called from XSLT. This parameter can be either a string (a function name) or an array of functions.
     * @return void No value is returned.
     * @since 5.0
     */
    public function registerPHPFunctions(array|string|null $functions = null): void {}

    /**
     * Sets profiling output file
     * @param string $filename Path to the file to dump profiling information.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function setProfiling(string|null $filename) {}

    /**
     * Set security preferences
     * @param int $preferences The new security preferences. The following constants can be ORed: XSL_SECPREF_READ_FILE, XSL_SECPREF_WRITE_FILE, XSL_SECPREF_CREATE_DIRECTORY, XSL_SECPREF_READ_NETWORK, XSL_SECPREF_WRITE_NETWORK. Alternatively, XSL_SECPREF_NONE or XSL_SECPREF_DEFAULT can be passed.
     * @return int Returns the old security preferences.
     * @since 5.4
     */
    public function setSecurityPrefs(int $preferences): int {}

    /**
     * Get security preferences
     * @return int A bitmask consisting of XSL_SECPREF_READ_FILE, XSL_SECPREF_WRITE_FILE, XSL_SECPREF_CREATE_DIRECTORY, XSL_SECPREF_READ_NETWORK, XSL_SECPREF_WRITE_NETWORK.
     * @since 5.4
     */
    public function getSecurityPrefs(): int {}
}
