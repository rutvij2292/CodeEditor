<?php

/**
 * The DOMAttr interface represents an attribute in an DOMElement object.
 */
class DOMAttr extends DOMNode
{
    /**
     * @var string The name of the attribute
     */
    public string $name;

    /**
     * @var DOMElement The element which contains the attribute
     */
    public DOMElement|null $ownerElement;

    /**
     * @var bool Not implemented yet, always is NULL
     */
    public mixed $schemaTypeInfo;

    /**
     * @var bool Not implemented yet, always is NULL
     */
    public bool $specified;

    /**
     * @var string The value of the attribute
     */
    public string $value;

    /**
     * Checks if attribute is a defined ID
     * @return bool true on success or false on failure.
     */
    public function isId(): bool {}

    /**
     * Creates a new DOMAttr object
     * @param string $name The tag name of the attribute.
     * @param string $value [optional] The value of the attribute.
     * @throws DOMException If invalid $name
     */
    public function __construct(
        string $name,
        string $value = ''
    ) {}
}
