<?php

/**
 * A class for working with PHP tokens, which is an alternative to
 * the token_get_all() function.
 * @since 8.0
 */
class PhpToken implements Stringable
{
    /**
     * One of the T_* constants, or an integer < 256 representing a
     * single-char token.
     */
    public int $id;

    /**
     * The textual content of the token.
     */
    public string $text;

    /**
     * The starting line number (1-based) of the token.
     */
    public int $line;

    /**
     * The starting position (0-based) in the tokenized string.
     */
    public int $pos;

    /**
     * Returns a new PhpToken object
     * @param int $id An integer identifier
     * @param string $text Textual content
     * @param int $line Strating line
     * @param int $pos Straring position (line offset)
     */
    final public function __construct(int $id, string $text, int $line = -1, int $pos = -1) {}

    /**
     * Get the name of the token.
     * @return string|null An ASCII character for single-char tokens, or one of T_* constant names for known tokens (see ), or null for unknown tokens.
     */
    public function getTokenName(): ?string {}

    /**
     * Same as token_get_all(), but returning array of PhpToken
     * or an instance of a child class.
     * @param string $code An a PHP source code
     * @param int $flags Valid flags: TOKEN_PARSE - Recognises the ability to use reserved words in specific contexts.
     * @return static[] An array of PHP tokens represented by instances of PhpToken or its descendants. This method returns static[] so that PhpToken can be seamlessly extended.
     */
    public static function tokenize(string $code, int $flags = 0): array {}

    /**
     * Whether the token has the given ID, the given text, or has an ID/text
     * part of the given array.
     * @param int|string|array $kind Either a single value to match the token's id or textual content, or an array thereof.
     * @return bool A boolean value whether the token is of given kind.
     */
    public function is($kind): bool {}

    /**
     * Whether this token would be ignored by the PHP parser.
     * @return bool A boolean value whether the token would be ignored by the PHP parser (such as whitespace or comments).
     */
    public function isIgnorable(): bool {}

    /**
     * {@inheritDoc}
     */
    public function __toString(): string {}
}
