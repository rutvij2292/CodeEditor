<?php

/**
 * Returns information about the given hash
 * @param string $hash A hash created by password_hash().
 * @return array|null Returns an associative array with three elements: algo, which will match a password algorithm constant algoName, which has the human readable name of the algorithm options, which includes the options provided when calling  @link ...
 * @since 5.5
 */
function password_get_info(string $hash): array {}

/**
 * Creates a password hash.
 * @param string $password The user's password.
 * @param string|int|null $algo A password algorithm constant  denoting the algorithm to use when hashing the password.
 * @param array $options [optional]  An associative array containing options. See the password algorithm constants for documentation on the supported options for each algorithm. If omitted, a random salt will be created and the default cost will be used. Warning The salt option has been deprecated as ...
 * @return string|false|null Returns the hashed password, or FALSE on failure (PRIOR PHP 8.0), or null if the algorithm is invalid
 * @since 5.5
 */
function password_hash(string $password, string|int|null $algo, array $options = []): string {}

/**
 * Checks if the given hash matches the given options.
 * @param string $hash A hash created by password_hash().
 * @param string|int|null $algo A password algorithm constant denoting the algorithm to use when hashing the password.
 * @param array $options [optional]  An associative array containing options. See the password algorithm constants for documentation on the supported options for each algorithm.
 * @return bool Returns TRUE if the hash should be rehashed to match the given algo and options, or FALSE otherwise.
 * @since 5.5
 */
function password_needs_rehash(string $hash, string|int|null $algo, array $options = []): bool {}

/**
 * Checks if the given hash matches the given options.
 * @param string $password The user's password.
 * @param string $hash A hash created by password_hash().
 * @return bool Returns TRUE if the password and hash match, or FALSE otherwise.
 * @since 5.5
 */
function password_verify(string $password, string $hash): bool {}

/**
 * Return a complete list of all registered password hashing algorithms.
 * @return string[] Returns the available password hashing algorithm IDs.
 * @since 7.4
 */
function password_algos(): array {}
