<?php

/**
 * The DOMText class inherits from DOMCharacterData and represents the textual content of
 * a DOMElement or DOMAttr.
 */
class DOMText extends DOMCharacterData
{
    /**
     * Holds all the text of logically-adjacent (not separated by Element, Comment or Processing Instruction) Text nodes.
     */
    public string $wholeText;

    /**
     * Breaks this node into two nodes at the specified offset
     * @param int $offset The offset at which to split, starting from 0.
     * @return DOMText The new node of the same type, which contains all the content at and after the offset.
     */
    public function splitText(int $offset) {}

    /**
     * Indicates whether this text node contains whitespace
     * @return bool true on success or false on failure.
     */
    public function isWhitespaceInElementContent(): bool {}

    /**
     * Returns whether this text node contains whitespace in element content
     * @return bool Returns true on success or false on failure.
     */
    public function isElementContentWhitespace(): bool {}

    /**
     * @param $content
     * @removed 8.0
     */
    public function replaceWholeText($content) {}

    /**
     * Creates a new DOMText object
     * @param string $data [optional] The value of the text node. If not supplied an empty text node is created.
     */
    public function __construct(string $data = '') {}
}
