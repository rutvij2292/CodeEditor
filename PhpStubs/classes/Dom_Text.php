<?php
namespace Dom;

/**
 * The Dom\Text class inherits from Dom\CharacterData and represents a text node.
 *
 * This is the modern, spec-compliant equivalent of DOMText.
 * @since 8.4
 */
class Text extends CharacterData
{
    /**
     * Breaks this node into two nodes at the specified offset
     *
     * Breaks this node into two nodes at the specified offset, keeping both in the tree as
     * siblings.
     * @param int $offset The offset at which to split, starting from 0.
     * @return Text The new node of the same type, which contains all the content at and after the offset.
     */
    public function splitText(int $offset): Text {}

    public string $wholeText;
}
