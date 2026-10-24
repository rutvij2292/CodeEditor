<?php

/**
 * The DOMCharacterData class represents nodes with character data.
 * No nodes directly correspond to this class, but other nodes do inherit from it.
 */
class DOMCharacterData extends DOMNode implements DOMChildNode
{
    /**
     * @var string The contents of the node.
     */
    public string $data;

    /**
     * @var int The length of the contents.
     */
    public int $length;

    public DOMElement|null $nextElementSibling;

    public DOMElement|null $previousElementSibling;

    /**
     * Extracts a range of data from the node
     * @param int $offset Start offset of substring to extract.
     * @param int $count The number of characters to extract.
     * @return string The specified substring. If the sum of offset and count exceeds the length, then all 16-bit units to the end of the data are returned.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INDEX_SIZE_ERR Raised if offset is negative or greater than the number of UTF-8 codepoints in data, or if count is negative.
     */
    public function substringData(
        int $offset,
        int $count
    ) {}

    /**
     * Append the string to the end of the character data of the node
     * @param string $data The string to append.
     */
    public function appendData(string $data): true {}

    /**
     * Insert a string at the specified 16-bit unit offset
     * @param int $offset The character offset at which to insert.
     * @param string $data The string to insert.
     * @return bool Returns true on success or false on failure.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INDEX_SIZE_ERR Raised if offset is negative or greater than the number of UTF-8 codepoints in data.
     */
    public function insertData(
        int $offset,
        string $data
    ): bool {}

    /**
     * Remove a range of characters from the node
     * @param int $offset The offset from which to start removing.
     * @param int $count The number of characters to delete. If the sum of offset and count exceeds the length, then all characters to the end of the data are deleted.
     * @return bool Returns true on success or false on failure.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INDEX_SIZE_ERR Raised if offset is negative or greater than the number of UTF-8 codepoints in data, or if count is negative.
     */
    public function deleteData(
        int $offset,
        int $count
    ): bool {}

    /**
     * Replace a substring within the DOMCharacterData node
     * @param int $offset The offset from which to start replacing.
     * @param int $count The number of characters to replace. If the sum of offset and count exceeds the length, then all characters to the end of the data are replaced.
     * @param string $data The string with which the range must be replaced.
     * @return bool Returns true on success or false on failure.
     * @throws \DOMException May throw a DOMException with the following error codes: DOM_INDEX_SIZE_ERR Raised if offset is negative or greater than the number of UTF-8 codepoints in data, or if count is negative.
     */
    public function replaceData(
        int $offset,
        int $count,
        string $data
    ): bool {}

    /**
     * {@inheritDoc}
     */
    public function remove(): void {}

    /**
     * {@inheritDoc}
     */
    public function before(...$nodes): void {}

    /**
     * {@inheritDoc}
     */
    public function after(...$nodes): void {}

    /**
     * {@inheritDoc}
     */
    public function replaceWith(...$nodes): void {}
}
