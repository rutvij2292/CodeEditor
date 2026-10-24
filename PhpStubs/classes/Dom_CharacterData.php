<?php
namespace Dom;

/**
 * Represents nodes with character data. No nodes directly correspond to this class, but other nodes
 * do inherit from it.
 *
 * This is the modern, spec-compliant equivalent of DOMCharacterData.
 * @since 8.4
 */
class CharacterData extends Node implements ChildNode
{
    public ?Element $previousElementSibling;

    public ?Element $nextElementSibling;

    public string $data;

    public int $length;

    /**
     * Extracts a range of data from the character data
     *
     * Returns the specified substring.
     * @param int $offset Start offset of substring to extract.
     * @param int $count The number of characters to extract.
     * @return string The specified substring. If the sum of offset and count exceeds the length, then all UTF-8 codepoints to the end of the data are returned.
     */
    public function substringData(int $offset, int $count): string {}

    /**
     * Append the string to the end of the character data of the node
     *
     * Append the string data to the end of the character data of the node.
     * @param string $data The string to append.
     */
    public function appendData(string $data): void {}

    /**
     * Insert a string at the specified UTF-8 codepoint offset
     *
     * Inserts string data at position offset.
     * @param int $offset The character offset at which to insert.
     * @param string $data The string to insert.
     */
    public function insertData(int $offset, string $data): void {}

    /**
     * Remove a range of characters from the character data
     *
     * Deletes count characters starting from position offset.
     * @param int $offset The offset from which to start removing.
     * @param int $count The number of characters to delete. If the sum of offset and count exceeds the length, then all characters to the end of the data are deleted.
     */
    public function deleteData(int $offset, int $count): void {}

    /**
     * Replace a substring within the character data
     *
     * Replace count characters starting from position offset with data.
     * @param int $offset The offset from which to start replacing.
     * @param int $count The number of characters to replace. If the sum of offset and count exceeds the length, then all characters to the end of the data are replaced.
     * @param string $data The string with which the range must be replaced.
     */
    public function replaceData(int $offset, int $count, string $data): void {}

    /**
     * Removes the character data node
     * @return void No value is returned.
     */
    public function remove(): void {}

    /**
     * Adds nodes before the character data
     *
     * Adds the passed nodes before the character data.
     * @param Node|string $nodes Nodes to be added before the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function before(Node|string ...$nodes): void {}

    /**
     * Adds nodes after the character data
     *
     * Adds the passed nodes after the character data.
     * @param Node|string $nodes Nodes to be added after the node. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function after(Node|string ...$nodes): void {}

    /**
     * Replaces the character data with new nodes
     * @param Node|string $nodes The replacement nodes. Strings are automatically converted to text nodes.
     * @return void No value is returned.
     */
    public function replaceWith(Node|string ...$nodes): void {}
}
