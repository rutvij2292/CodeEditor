<?php

/**
 * The DOMXPath class (supports XPath 1.0)
 */
class DOMXPath
{
    /**
     * @var DOMDocument
     */
    public DOMDocument $document;

    public bool $registerNodeNamespaces;

    /**
     * Creates a new DOMXPath object
     * @param DOMDocument $document The DOMDocument associated with the DOMXPath.
     * @param bool $registerNodeNS [optional] allow global flag to configure query() or evaluate() calls. Since 8.0.
     */
    public function __construct(DOMDocument $document, bool $registerNodeNS = true) {}

    /**
     * Registers the namespace with the DOMXPath object
     * @param string $prefix The prefix.
     * @param string $namespace The URI of the namespace.
     * @return bool true on success or false on failure.
     */
    public function registerNamespace(
        string $prefix,
        string $namespace
    ): bool {}

    /**
     * Evaluates the given XPath expression
     * @param string $expression The XPath expression to execute.
     * @param DOMNode $contextNode [optional] The optional contextnode can be specified for doing relative XPath queries. By default, the queries are relative to the root element.
     * @param bool $registerNodeNS [optional] The optional registerNodeNS can be specified to disable automatic registration of the context node.
     * @return DOMNodeList<DOMNode|DOMNameSpaceNode>|false a DOMNodeList containing all nodes matching the given XPath expression. Any expression which does not return nodes will return an empty DOMNodeList. The return is false if the expression is malformed or the contextnode is invalid.
     * @throws \Error Throws an Error if a PHP callback is invoked but there were no callbacks registered, or if the named callback was not registered. Throws a TypeError if the php:function syntax is used and the handler name is not a string. Throws an Error if a non-DOM object was returned from a ...
     * @throws \TypeError Throws an Error if a PHP callback is invoked but there were no callbacks registered, or if the named callback was not registered. Throws a TypeError if the php:function syntax is used and the handler name is not a string. Throws an Error if a non-DOM object was returned from a ...
     */
    public function query(
        string $expression,
        DOMNode|null $contextNode = null,
        bool $registerNodeNS = true
    ): mixed {}

    /**
     * Evaluates the given XPath expression and returns a typed result if possible.
     * @param string $expression The XPath expression to execute.
     * @param DOMNode $contextNode [optional] The optional contextnode can be specified for doing relative XPath queries. By default, the queries are relative to the root element.
     * @param bool $registerNodeNS [optional] The optional registerNodeNS can be specified to disable automatic registration of the context node.
     * @return mixed a typed result if possible or a DOMNodeList<DOMNode|DOMNameSpaceNode>|false containing all nodes matching the given XPath expression.
     */
    public function evaluate(
        string $expression,
        DOMNode|null $contextNode = null,
        bool $registerNodeNS = true
    ): mixed {}

    /**
     * Register PHP functions as XPath functions
     * @param string|string[] $restrict [optional] Use this parameter to only allow certain functions to be called from XPath. This parameter can be either a string (a function name) or an array of function names.
     * @return void No value is returned.
     * @throws \ValueError Throws a ValueError if a callback name is not valid. Throws a ValueError if options contains an invalid option. Throws a ValueError if overrideEncoding is an unknown encoding. Throws a TypeError if a given callback is not callable.
     * @throws \TypeError Throws a ValueError if a callback name is not valid. Throws a ValueError if options contains an invalid option. Throws a ValueError if overrideEncoding is an unknown encoding. Throws a TypeError if a given callback is not callable.
     */
    public function registerPhpFunctions(string|array|null $restrict = null): void {}

    /**
     * Register a PHP functions as namespaced XPath function
     *
     * This method enables the ability to use a PHP function as a namespaced XPath function inside
     * XPath expressions.
     * @since 8.4
     */
    public function registerPhpFunctionNS(string $namespaceURI, string $name, callable $callable): void {}

    /**
     * Quotes a string for use in an XPath expression
     *
     * Quotes str for use in an XPath expression.
     * @since 8.4
     */
    public static function quote(string $str): string {}
}
