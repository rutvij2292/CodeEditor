<?php

/**
 * The DOMProcessingInstruction class
 */
class DOMProcessingInstruction extends DOMNode
{
    public string $target;

    public string $data;

    /**
     * Creates a new DOMProcessingInstruction object
     * @param string $name The tag name of the processing instruction.
     * @param string $value [optional] The value of the processing instruction.
     */
    public function __construct(
        string $name,
        string $value = ''
    ) {}
}
