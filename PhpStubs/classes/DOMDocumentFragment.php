<?php

/**
 * The DOMDocumentFragment class
 */
class DOMDocumentFragment extends DOMNode implements DOMParentNode
{
    public int $childElementCount;

    public DOMElement|null $lastElementChild;

    public DOMElement|null $firstElementChild;

    /**
     * Constructs a DOMDocumentFragment object
     */
    public function __construct() {}

    /**
     * Append raw XML data
     * @param string $data XML to append.
     * @return bool true on success or false on failure.
     */
    public function appendXML(string $data): bool {}

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
}
