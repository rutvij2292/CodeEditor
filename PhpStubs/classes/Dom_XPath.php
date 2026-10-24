<?php
namespace Dom;

/**
 * Allows to use XPath 1.0 queries on HTML or XML documents.
 *
 * This is the modern, spec-compliant equivalent of DOMXPath.
 * @since 8.4
 */
final class XPath
{
    public Document $document;

    public bool $registerNodeNamespaces;

    public function __construct(Document $document, bool $registerNodeNS = true) {}

    /**
     * @return null|bool|float|string|NodeList<Node>
     */
    public function evaluate(string $expression, ?Node $contextNode = null, bool $registerNodeNS = true): null|bool|float|string|NodeList {}

    /**
     * @return NodeList<Node>
     */
    public function query(string $expression, ?Node $contextNode = null, bool $registerNodeNS = true): NodeList {}

    public function registerNamespace(string $prefix, string $namespace): bool {}

    public function registerPhpFunctions(string|array|null $restrict = null): void {}

    public function registerPhpFunctionNS(string $namespaceURI, string $name, callable $callable): void {}

    public static function quote(string $str): string {}
}
