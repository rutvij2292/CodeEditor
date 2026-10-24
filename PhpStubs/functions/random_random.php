<?php

/**
 * Combined linear congruential generator
 * @return float A pseudo random float value in the range of (0, 1)
 */
function lcg_value(): float {}

/**
 * Seeds the Mersenne Twister Random Number Generator
 * @param int|null $seed An optional seed value
 * @param int $mode [optional] Use one of the following constants to specify the implementation of the algorithm to use.
 * @return void No value is returned.
 */
function mt_srand(
        int|null $seed = null,
        int $mode = MT_RAND_MT19937
    ): void {}

/**
 * Seed the random number generator
 * Note: As of PHP 7.1.0, srand() has been made
 * an alias of mt_srand().
 * @param int|null $seed Optional seed value
 * @param int $mode [optional] Use one of the following constants to specify the implementation of the algorithm to use.
 * @return void No value is returned.
 */
function srand(
        int|null $seed = null,
        int $mode = MT_RAND_MT19937
    ): void {}

/**
 * Generate a random integer
 * @param int $min [optional]
 * @param int $max [optional]
 * @return int A pseudo random value between min (or 0) and max (or getrandmax, inclusive).
 */
function rand(int $min, int $max): int {}

/**
 * Generate a random value via the Mersenne Twister Random Number Generator
 * @param int $min [optional] Optional lowest value to be returned (default: 0)
 * @param int $max [optional] Optional highest value to be returned (default: mt_getrandmax())
 * @return int A random integer value between min (or 0) and max (or mt_getrandmax, inclusive)
 * @throws \ValueError If max is less than min, a ValueError will be thrown.
 */
function mt_rand(int $min, int $max): int {}

/**
 * Show largest possible random value
 * @return int the maximum random value returned by mt_rand
 */
function mt_getrandmax(): int {}

/**
 * Show largest possible random value
 * @return int The largest possible random value returned by rand
 */
function getrandmax(): int {}

/**
 * Generates cryptographically secure pseudo-random bytes
 * @param int $length The length of the random string that should be returned in bytes.
 * @return string Returns a string containing the requested number of cryptographically secure random bytes.
 * @since 7.0
 * @throws Random\RandomException if an appropriate source of randomness cannot be found.
 */
function random_bytes(int $length): string {}

/**
 * Generates cryptographically secure pseudo-random integers
 * @param int $min The lowest value to be returned, which must be PHP_INT_MIN or higher.
 * @param int $max The highest value to be returned, which must be less than or equal to PHP_INT_MAX.
 * @return int Returns a cryptographically secure random integer in the range min to max, inclusive.
 * @since 7.0
 * @throws Random\RandomException if an appropriate source of randomness cannot be found.
 */
function random_int(int $min, int $max): int {}
