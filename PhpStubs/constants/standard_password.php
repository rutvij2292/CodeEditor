<?php

const PASSWORD_DEFAULT = "2y";

/**
 * The default cost used for the BCRYPT hashing algorithm.
 *
 * Values for this constant:
 *
 * PHP 5.6.0 - PASSWORD_BCRYPT_DEFAULT_COST
 */
const PASSWORD_BCRYPT_DEFAULT_COST = 12;

/**
 * The default algorithm to use for hashing if no algorithm is provided.
 * This may change in newer PHP releases when newer, stronger hashing
 * algorithms are supported.
 *
 * It is worth noting that over time this constant can (and likely will)
 * change. Therefore you should be aware that the length of the resulting
 * hash can change. Therefore, if you use PASSWORD_DEFAULT
 * you should store the resulting hash in a way that can store more than 60
 * characters (255 is the recommended width).
 *
 * Values for this constant:
 *
 * PHP 5.5.0 - PASSWORD_BCRYPT
 */
const PASSWORD_BCRYPT = '2y';

/**
 * PASSWORD_ARGON2I is used to create new password hashes using the Argon2i algorithm.
 *
 * Supported Options:
 *
 * memory_cost (integer) - Maximum memory (in bytes) that may be used to compute the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_MEMORY_COST.
 *
 * time_cost (integer) - Maximum amount of time it may take to compute the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_TIME_COST.
 *
 * threads (integer) - Number of threads to use for computing the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_THREADS.
 *
 * Available as of PHP 7.2.0.
 * @since 7.2
 */
const PASSWORD_ARGON2I = 'argon2i';

/**
 * PASSWORD_ARGON2ID is used to create new password hashes using the Argon2id algorithm.
 *
 * Supported Options:
 *
 * memory_cost (integer) - Maximum memory (in bytes) that may be used to compute the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_MEMORY_COST.
 *
 * time_cost (integer) - Maximum amount of time it may take to compute the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_TIME_COST.
 *
 * threads (integer) - Number of threads to use for computing the Argon2 hash. Defaults to PASSWORD_ARGON2_DEFAULT_THREADS.
 *
 * Available as of PHP 7.3.0.
 * @since 7.3
 */
const PASSWORD_ARGON2ID = 'argon2id';

/**
 * Default amount of memory in bytes that Argon2lib will use while trying to compute a hash.
 * Available as of PHP 7.2.0.
 * @since 7.2
 */
const PASSWORD_ARGON2_DEFAULT_MEMORY_COST = 65536;

/**
 * Default amount of time that Argon2lib will spend trying to compute a hash.
 * Available as of PHP 7.2.0.
 * @since 7.2
 */
const PASSWORD_ARGON2_DEFAULT_TIME_COST = 4;

/**
 * Default number of threads that Argon2lib will use.
 * Available as of PHP 7.2.0.
 * @since 7.2
 */
const PASSWORD_ARGON2_DEFAULT_THREADS = 1;

/**
 * @since 7.4
 */
const PASSWORD_ARGON2_PROVIDER = 'standard';
