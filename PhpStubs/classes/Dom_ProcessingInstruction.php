<?php
namespace Dom;

/**
 * This represents a processing instruction (PI) node. These are meant to indicate data areas meant
 * for processing by specific applications.
 *
 * This is the modern, spec-compliant equivalent of DOMProcessingInstruction.
 * @since 8.4
 */
class ProcessingInstruction extends CharacterData
{
    public string $target;
}
