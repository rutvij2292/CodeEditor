<?php

/**
 * Split given source into PHP tokens
 * @param string $code The PHP source to parse.
 * @param int $flags Valid flags: TOKEN_PARSE - Recognises the ability to use reserved words in specific contexts.
 * @return array An array of token identifiers. Each individual token identifier is either a single character (i.e.: ;, ., >, !, etc...), or a three element array containing the token index in element 0, the string content of the original token in element 1 and the line number in element 2.
 */
function token_get_all(string $code, int $flags = 0): array {}

/**
 * Get the symbolic name of a given PHP token
 * @param int $id The token value.
 * @return string The symbolic name of the given token.
 */
function token_name(int $id): string {}
