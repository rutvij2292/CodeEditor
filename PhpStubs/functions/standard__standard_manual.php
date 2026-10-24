<?php

/**
 * Convert hexadecimal string to its binary representation.
 *
 * If the hexadecimal input string is of odd length or invalid hexadecimal string an E_WARNING level error is emitted.
 * @param string $string Hexadecimal string to convert.
 * @return string|false The binary representation of the given data or FALSE on failure.
 * @see bin2hex()
 * @see unpack()
 * @since 5.4
 */
function hex2bin(string $string): string|false {}

/**
 * Get or Set the HTTP response code
 * @param int $response_code The optional response_code will set the response code.
 * @return int|bool The current response code. By default the return value is int(200).
 */
function http_response_code(int $response_code = 0): int|bool {}
