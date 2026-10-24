<?php

/**
 * Generate a hash value (message digest)
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..)
 * @param string $data Message to be hashed.
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @param array $options An array of options for the various hashing algorithms. Currently, only the "seed" parameter is supported by the MurmurHash variants.
 * @return string a string containing the calculated message digest as lowercase hexits unless binary is set to true in which case the raw binary representation of the message digest is returned.
 * @throws \ValueError Throws a ValueError exception if algo is unknown.
 */
function hash(string $algo, string $data, bool $binary = false, array $options = []): string {}

/**
 * Timing attack safe string comparison
 * @param string $known_string The known string that must be kept secret.
 * @param string $user_string The user-supplied string to compare against.
 * @return bool Returns TRUE when the two strings are equal, FALSE otherwise.
 * @since 5.6
 */
function hash_equals(string $known_string, string $user_string): bool {}

/**
 * Generate a hash value using the contents of a given file
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..)
 * @param string $filename URL describing location of file to be hashed; Supports fopen wrappers.
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @param array $options An array of options for the various hashing algorithms. Currently, only the "seed" parameter is supported by the MurmurHash variants.
 * @return string|false a string containing the calculated message digest as lowercase hexits unless binary is set to true in which case the raw binary representation of the message digest is returned.
 */
function hash_file(string $algo, string $filename, bool $binary = false, array $options = []): string|false {}

/**
 * Generate a keyed hash value using the HMAC method
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..) See hash_algos for a list of supported algorithms. Since 7.2.0 usage of non-cryptographic hash functions (adler32, crc32, crc32b, fnv132, fnv1a32, fnv164, fnv1a64, joaat) was disabled.
 * @param string $data Message to be hashed.
 * @param string $key Shared secret key used for generating the HMAC variant of the message digest.
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @return string a string containing the calculated message digest as lowercase hexits unless binary is set to true in which case the raw binary representation of the message digest is returned.
 * @throws \ValueError Throws a ValueError exception if algo is unknown or is a non-cryptographic hash function.
 */
function hash_hmac(string $algo, string $data, string $key, bool $binary = false): string {}

/**
 * Generate a keyed hash value using the HMAC method and the contents of a given file
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..) See hash_algos for a list of supported algorithms. Since 7.2.0 usage of non-cryptographic hash functions (adler32, crc32, crc32b, fnv132, fnv1a32, fnv164, fnv1a64, joaat) was disabled.
 * @param string $filename URL describing location of file to be hashed; Supports fopen wrappers.
 * @param string $key Shared secret key used for generating the HMAC variant of the message digest.
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @return string|false a string containing the calculated message digest as lowercase hexits unless binary is set to true in which case the raw binary representation of the message digest is returned.
 * @throws \ValueError Throws a ValueError exception if algo is unknown or is a non-cryptographic hash function.
 */
function hash_hmac_file(string $algo, string $filename, string $key, bool $binary = false): string|false {}

/**
 * Initialize an incremental hashing context
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..). For a list of supported algorithms see hash_algos. Since 7.2.0 usage of non-cryptographic hash functions (adler32, crc32, crc32b, fnv132, fnv1a32, fnv164, fnv1a64, joaat) was disabled.
 * @param int $flags [optional] Optional settings for hash generation, currently supports only one option: HASH_HMAC. When specified, the key must be specified.
 * @param string $key When HASH_HMAC is specified for options, a shared secret key to be used with the HMAC hashing method must be supplied in this parameter.
 * @param array $options An array of options for the various hashing algorithms. Currently, only the "seed" parameter is supported by the MurmurHash variants.
 * @return HashContext|resource a Hashing Context resource for use with hash_update, hash_update_stream, hash_update_file, and hash_final.
 * @throws \ValueError Throws a ValueError exception if algo is unknown or is a non-cryptographic hash function, or if key is empty. Passing configurations options of the wrong type in options will now emit an E_DEPRECATED error because they can be interpreted incorrectly. This will become a ...
 */
function hash_init(string $algo, int $flags = 0, string $key = "", array $options = []): HashContext {}

/**
 * Pump data into an active hashing context
 * @param HashContext|resource $context Hashing context returned by hash_init.
 * @param string $data Message to be included in the hash digest.
 * @return bool TRUE.
 */
function hash_update(HashContext $context, string $data): bool {}

/**
 * Pump data into an active hashing context from an open stream
 * @param HashContext|resource $context Hashing context returned by hash_init.
 * @param resource $stream Open file handle as returned by any stream creation function.
 * @param int $length [optional] Maximum number of characters to copy from handle into the hashing context.
 * @return int Actual number of bytes added to the hashing context from handle.
 */
function hash_update_stream(HashContext $context, $stream, int $length = -1): int {}

/**
 * Pump data into an active hashing context from a file
 * @param HashContext|resource $context Hashing context returned by hash_init.
 * @param string $filename URL describing location of file to be hashed; Supports fopen wrappers.
 * @param resource $stream_context [optional] Stream context as returned by stream_context_create.
 * @return bool TRUE on success or FALSE on failure.
 */
function hash_update_file(HashContext $context, string $filename, $stream_context = null): bool {}

/**
 * Finalize an incremental hash and return resulting digest
 * @param HashContext|resource $context Hashing context returned by hash_init.
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @return string a string containing the calculated message digest as lowercase hexits unless binary is set to true in which case the raw binary representation of the message digest is returned.
 */
function hash_final(HashContext $context, bool $binary = false): string {}

/**
 * Copy hashing context
 * @param HashContext|resource $context Hashing context returned by hash_init.
 * @return HashContext|resource a copy of Hashing Context resource.
 */
function hash_copy(HashContext $context): HashContext {}

/**
 * Return a list of registered hashing algorithms
 * @return array a numerically indexed array containing the list of supported hashing algorithms.
 */
function hash_algos(): array {}

/**
 * Generate a hkdf key derivation of a supplied key input
 * @param string $algo Name of selected hashing algorithm (i.e. "sha256", "sha512", "haval160,4", etc..) See hash_algos() for a list of supported algorithms. Note Non-cryptographic hash functions are not allowed.
 * @param string $key Input keying material (raw binary). Cannot be empty.
 * @param int $length [optional] Desired output length in bytes. Cannot be greater than 255 times the chosen hash function size. If length is 0, the output length will default to the chosen hash function size.
 * @param string $info [optional] Application/context-specific info string.
 * @param string $salt [optional] Salt to use during derivation. While optional, adding random salt significantly improves the strength of HKDF.
 * @return string|false Returns a string containing a raw binary representation of the derived key (also known as output keying material - OKM); or FALSE on failure.
 * @since 7.1 Generate a HKDF key derivation of a supplied key input
 * @throws \ValueError Throws a ValueError exception if key is empty, algo is unknown/non-cryptographic, length is less than 0 or too large (greater than 255 times the size of the hash function).
 */
function hash_hkdf(string $algo, string $key, int $length = 0, string $info = '', string $salt = ''): string {}

/**
 * Return a list of registered hashing algorithms suitable for hash_hmac
 * @since 7.2 Return a list of registered hashing algorithms suitable for hash_hmac
 * @return string[] Returns a numerically indexed array containing the list of supported hashing algorithms suitable for hash_hmac().
 */
function hash_hmac_algos(): array {}

/**
 * Generate a PBKDF2 key derivation of a supplied password
 * @param string $algo Name of selected hashing algorithm (i.e. "md5", "sha256", "haval160,4", etc..) See hash_algos for a list of supported algorithms. Since 7.2.0 usage of non-cryptographic hash functions (adler32, crc32, crc32b, fnv132, fnv1a32, fnv164, fnv1a64, joaat) was disabled.
 * @param string $password The password to use for the derivation.
 * @param string $salt The salt to use for the derivation. This value should be generated randomly.
 * @param int $iterations The number of internal iterations to perform for the derivation.
 * @param int $length [optional] The length of the output string. If binary is TRUE this corresponds to the byte-length of the derived key, if binary is FALSE this corresponds to twice the byte-length of the derived key (as every byte of the key is returned as two hexits). If 0 is passed, the entire ...
 * @param bool $binary [optional] When set to TRUE, outputs raw binary data. FALSE outputs lowercase hexits.
 * @param array $options [optional] Additional options. This parameter was added for PHP 8.1 only.
 * @return string a string containing the derived key as lowercase hexits unless binary is set to TRUE in which case the raw binary representation of the derived key is returned.
 * @since 5.5
 * @throws \ValueError Throws a ValueError exception if the algorithm is unknown, the iterations parameter is less than or equal to 0, the length is less than 0 or the salt is too long (greater than INT_MAX - 4).
 */
function hash_pbkdf2(
    string $algo,
    string $password,
    string $salt,
    int $iterations,
    int $length = 0,
    bool $binary = false,
    array $options = []
): string {}

/**
 * Generates a key
 * @param int $algo The hash ID used to create the key. One of the MHASH_hashname constants.
 * @param string $password An user supplied password.
 * @param string $salt Must be different and random enough for every key you generate in order to create different keys. Because salt must be known when you check the keys, it is a good idea to append the key to it. Salt has a fixed length of 8 bytes and will be padded with zeros if you supply less ...
 * @param int $length The key length, in bytes.
 * @return string|false the generated key as a string, or FALSE on error.
 * @deprecated
 */
function mhash_keygen_s2k(int $algo, string $password, string $salt, int $length): string|false {}

/**
 * Gets the block size of the specified hash
 * @param int $algo The hash ID. One of the MHASH_hashname constants.
 * @return int|false the size in bytes or FALSE, if the hash does not exist.
 * @deprecated
 */
function mhash_get_block_size(int $algo): int|false {}

/**
 * Gets the name of the specified hash
 * @param int $algo The hash ID. One of the MHASH_hashname constants.
 * @return string|false the name of the hash or FALSE, if the hash does not exist.
 * @deprecated
 */
function mhash_get_hash_name(int $algo): string|false {}

/**
 * Gets the highest available hash ID
 * @return int<0, max> the highest available hash ID. Hashes are numbered from 0 to this hash ID.
 * @deprecated
 */
function mhash_count(): int {}

/**
 * Computes hash
 * @param int $algo The hash ID. One of the MHASH_hashname constants.
 * @param string $data The user input, as a string.
 * @param string|null $key [optional] If specified, the function will return the resulting HMAC instead. HMAC is keyed hashing for message authentication, or simply a message digest that depends on the specified key. Not all algorithms supported in mhash can be used in HMAC mode.
 * @return string|false the resulting hash (also called digest) or HMAC as a string, or FALSE on error.
 * @deprecated
 */
function mhash(int $algo, string $data, ?string $key = null): string|false {}
