<?php
namespace Dom;

/**
 * Represents a set of tokens in an attribute (e.g. class names).
 * @since 8.4
 */
final class TokenList implements \IteratorAggregate, \Countable
{
    private function __construct() {}

    public int $length;

    /**
     * Returns a token from the list
     *
     * Returns a token from the list at index.
     * @param int $index The token index.
     * @return string|null Returns the token at index or null when the index is out of bounds.
     */
    public function item(int $index): ?string {}

    /**
     * Returns whether the list contains a given token
     *
     * Returns whether the list contains token.
     * @param string $token The token.
     * @return bool Returns true if the list contains token, false otherwise.
     */
    public function contains(string $token): bool {}

    /**
     * Adds the given tokens to the list
     *
     * Adds the given tokens to the list, but not any that were already present.
     * @param string $tokens The tokens to add.
     * @return void No value is returned.
     * @throws \ValueError Throws a ValueError if a token contains any null bytes. Throws a
     * @throws \DOMException with code Dom\SYNTAX_ERR if a token is the empty string. Throws a
     * @throws \DOMException with code Dom\INVALID_CHARACTER_ERR if a token contains any ASCII whitespace.
     */
    public function add(string ...$tokens): void {}

    /**
     * Removes the given tokens from the list
     *
     * Removes the given tokens from the list, but ignores any that were not present.
     * @param string $tokens The tokens to remove.
     * @return void No value is returned.
     * @throws \ValueError Throws a ValueError if a token contains any null bytes. Throws a
     * @throws \DOMException with code Dom\SYNTAX_ERR if a token is the empty string. Throws a
     * @throws \DOMException with code Dom\INVALID_CHARACTER_ERR if a token contains any ASCII whitespace.
     */
    public function remove(string ...$tokens): void {}

    /**
     * Toggles the presence of a token in the list
     *
     * Toggles the presence of token in the list.
     * @param string $token The token to toggle.
     * @param bool|null $force If force is provided, setting it to true will add the token, and setting it to false will remove the token.
     * @return bool Returns true if the token is in the list after the call, false otherwise.
     * @throws \ValueError Throws a ValueError if a token contains any null bytes. Throws a
     * @throws \DOMException with code Dom\SYNTAX_ERR if a token is the empty string. Throws a
     * @throws \DOMException with code Dom\INVALID_CHARACTER_ERR if a token contains any ASCII whitespace.
     */
    public function toggle(string $token, ?bool $force = null): bool {}

    /**
     * Replaces a token in the list with another one
     * @param string $token The token to replace.
     * @param string $newToken The new token.
     * @return bool Returns true if token was in the list, false otherwise.
     * @throws \ValueError Throws a ValueError if a token contains any null bytes. Throws a
     * @throws \DOMException with code Dom\SYNTAX_ERR if a token is the empty string. Throws a
     * @throws \DOMException with code Dom\INVALID_CHARACTER_ERR if a token contains any ASCII whitespace.
     */
    public function replace(string $token, string $newToken): bool {}

    /**
     * Returns whether the given token is supported
     *
     * Returns whether token is in the associated attribute's supported tokens.
     * @param string $token The token.
     * @return bool Returns true on success or false on failure.
     * @throws \TypeError Throws a TypeError when the attribute does not define a supported tokens list.
     */
    public function supports(string $token): bool {}

    public string $value;

    /**
     * Returns the number of tokens in the list
     * @return int The number of tokens in the list.
     */
    public function count(): int {}

    /**
     * Returns an iterator over the token list
     * @return \Iterator An iterator over the token list.
     */
    public function getIterator(): \Iterator {}
}
