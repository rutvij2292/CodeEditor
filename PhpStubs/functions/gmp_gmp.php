<?php

/**
 * Create GMP number
 * @param mixed $num An integer or a string. The string representation can be decimal, hexadecimal or octal.
 * @param int $base [optional] The base. The base may vary from 2 to 36. If base is 0 (default value), the actual base is determined from the leading characters: if the first two characters are 0x or 0X, hexadecimal is assumed, otherwise if the first character is "0", octal is assumed, otherwise ...
 * @return resource|GMP A GMP number resource.
 */
function gmp_init(string|int $num, int $base = 0): GMP {}

/**
 * Convert GMP number to integer
 * @param resource|int|string|GMP $num A GMP number.
 * @return int An integer value of gmpnumber.
 */
function gmp_intval(GMP|string|int $num): int {}

/**
 * Sets the RNG seed
 * @param resource|string|int|GMP $seed The seed to be set for the gmp_random(), gmp_random_bits(), and gmp_random_range() functions. Either a GMP number resource in PHP 5.5 and earlier, a GMP object in PHP 5.6 and later, or a numeric string provided that it is possible to convert the latter to a ...
 * @return void|false
 * @since 7.0
 * @throws \ValueError Throws a ValueError if seed is invalid.
 */
function gmp_random_seed(GMP|string|int $seed): void {}

/**
 * Convert GMP number to string
 * @param resource|int|string|GMP $num The GMP number that will be converted to a string. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $base [optional] The base of the returned number. The default base is 10. Allowed values for the base are from 2 to 62 and -2 to -36.
 * @return string The number, as a string.
 */
function gmp_strval(GMP|string|int $num, int $base = 10): string {}

/**
 * Add numbers
 * @param resource|int|string|GMP $num1 A number that will be added. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 A number that will be added. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number representing the sum of the arguments.
 */
function gmp_add(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Subtract numbers
 * @param resource|string|GMP $num1 The number being subtracted from. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number subtracted from a. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_sub(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Multiply numbers
 * @param resource|string|GMP $num1 A number that will be multiplied by b. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 A number that will be multiplied by a. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_mul(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Divide numbers and get quotient and remainder
 * @param resource|string|GMP $num1 The number being divided. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number that n is being divided by. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $rounding_mode [optional] See the gmp_div_q function for description of the round argument.
 * @return array{resource|GMP, resource|GMP} an array, with the first element being [n/d] (the integer result of the division) and the second being (n - [n/d] * d) (the remainder of the division).
 */
function gmp_div_qr(GMP|string|int $num1, GMP|string|int $num2, int $rounding_mode = GMP_ROUND_ZERO): array {}

/**
 * Divide numbers
 * @param resource|string|GMP $num1 The number being divided. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number that a is being divided by. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $rounding_mode [optional] The result rounding is defined by the round, which can have the following values: GMP_ROUND_ZERO: The result is truncated towards 0.
 * @return resource|GMP A GMP number resource.
 */
function gmp_div_q(GMP|string|int $num1, GMP|string|int $num2, int $rounding_mode = GMP_ROUND_ZERO): GMP {}

/**
 * Remainder of the division of numbers
 * @param resource|string|GMP $num1 The number being divided. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number that n is being divided by. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $rounding_mode [optional] See the gmp_div_q function for description of the round argument.
 * @return resource|GMP The remainder, as a GMP number.
 */
function gmp_div_r(GMP|string|int $num1, GMP|string|int $num2, int $rounding_mode = GMP_ROUND_ZERO): GMP {}

/**
 * Divide numbers
 * @param resource|string|GMP $num1 The number being divided. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number that a is being divided by. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $rounding_mode [optional] The result rounding is defined by the round, which can have the following values: GMP_ROUND_ZERO: The result is truncated towards 0.
 * @return resource|GMP A GMP number resource.
 */
function gmp_div(GMP|string|int $num1, GMP|string|int $num2, int $rounding_mode = GMP_ROUND_ZERO): GMP {}

/**
 * Modulo operation
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The modulo that is being evaluated. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_mod(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Exact division of numbers
 * @param resource|string|GMP $num1 The number being divided. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 The number that a is being divided by. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_divexact(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Negate number
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP -a, as a GMP number.
 */
function gmp_neg(GMP|string|int $num): GMP {}

/**
 * Absolute value
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP the absolute value of a, as a GMP number.
 */
function gmp_abs(GMP|string|int $num): GMP {}

/**
 * Factorial
 * @param resource|string|GMP $num The factorial number. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_fact(GMP|string|int $num): GMP {}

/**
 * Calculate square root
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP The integer portion of the square root, as a GMP number.
 */
function gmp_sqrt(GMP|string|int $num): GMP {}

/**
 * Square root with remainder
 * @param resource|string|GMP $num The number being square rooted. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return array array where first element is the integer square root of a and the second is the remainder (i.e., the difference between a and the first element squared).
 */
function gmp_sqrtrem(GMP|string|int $num): array {}

/**
 * Raise number into power
 * @param resource|string|GMP $num The base number. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param positive-int $exponent The positive power to raise the base.
 * @return resource|GMP The new (raised) number, as a GMP number. The case of 0^0 yields 1.
 */
function gmp_pow(GMP|string|int $num, int $exponent): GMP {}

/**
 * Raise number into power with modulo
 * @param resource|string|GMP $num The base number. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $exponent The positive power to raise the base. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $modulus The modulo. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP The new (raised) number, as a GMP number.
 */
function gmp_powm(GMP|string|int $num, GMP|string|int $exponent, GMP|string|int $modulus): GMP {}

/**
 * Raise number into power with modulo, in constant time
 * @param GMP|string|int $num The base.
 * @param GMP|string|int $exponent The positive power to raise the num.
 * @param GMP|string|int $modulus The modulo, must be odd.
 * @return GMP The new (raised) number, as a GMP number.
 * @since 8.6
 */
function gmp_powm_sec(GMP|string|int $num, GMP|string|int $exponent, GMP|string|int $modulus): GMP {}

/**
 * Perfect square check
 * @param resource|string|GMP $num The number being checked as a perfect square. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return bool TRUE if a is a perfect square, FALSE otherwise.
 */
function gmp_perfect_square(GMP|string|int $num): bool {}

/**
 * Check if number is "probably prime"
 * @param resource|string|GMP $num The number being checked as a prime. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $repetitions [optional] Reasonable values of reps vary from 5 to 10 (default being 10); a higher value lowers the probability for a non-prime to pass as a "probable" prime. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a ...
 * @return int If this function returns 0, a is definitely not prime. If it returns 1, then a is "probably" prime. If it returns 2, then a is surely prime.
 */
function gmp_prob_prime(GMP|string|int $num, int $repetitions = 10): int {}

/**
 * Random number
 * @param int $bits The number of bits. Either a GMP number resource in PHP 5.5 and earlier, a GMP object in PHP 5.6 and later, or a numeric string provided that it is possible to convert the latter to a number.
 * @return GMP A random GMP number.
 * @throws \ValueError If bits is less than 1, a ValueError will be thrown.
 */
function gmp_random_bits(int $bits): GMP {}

/**
 * Random number
 * @param GMP|string|int $min A GMP number representing the lower bound for the random number
 * @param GMP|string|int $max A GMP number representing the upper bound for the random number
 * @return GMP A random GMP number.
 * @throws \ValueError If max is less than min, a ValueError will be thrown.
 */
function gmp_random_range(GMP|string|int $min, GMP|string|int $max): GMP {}

/**
 * Calculate GCD
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A positive GMP number that divides into both a and b.
 */
function gmp_gcd(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Calculate GCD and multipliers
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return array An array of GMP numbers.
 */
function gmp_gcdext(GMP|string|int $num1, GMP|string|int $num2): array {}

/**
 * Inverse by modulo
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP|false A GMP number on success or FALSE if an inverse does not exist.
 */
function gmp_invert(GMP|string|int $num1, GMP|string|int $num2): GMP|false {}

/**
 * Jacobi symbol
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number. Should be odd and must be positive.
 * @return int A GMP number resource.
 */
function gmp_jacobi(GMP|string|int $num1, GMP|string|int $num2): int {}

/**
 * Legendre symbol
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number. Should be odd and must be positive.
 * @return int A GMP number resource.
 */
function gmp_legendre(GMP|string|int $num1, GMP|string|int $num2): int {}

/**
 * Compare numbers
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return int a positive value if a > b, zero if a = b and a negative value if a < b.
 */
function gmp_cmp(GMP|string|int $num1, GMP|string|int $num2): int {}

/**
 * Sign of number
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return int 1 if a is positive, -1 if a is negative, and 0 if a is zero.
 */
function gmp_sign(GMP|string|int $num): int {}

/**
 * Random number
 * @param int $limiter [optional] The limiter. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A random GMP number.
 * @see gmp_random_bits()
 * @see gmp_random_range()
 * @removed 8.0
 * @deprecated Use see gmp_random_bits() or see gmp_random_range() instead
 */
function gmp_random($limiter = 20) {}

/**
 * Bitwise AND
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number representing the bitwise AND comparison.
 */
function gmp_and(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Bitwise OR
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_or(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Calculates one's complement
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP the one's complement of a, as a GMP number.
 */
function gmp_com(GMP|string|int $num): GMP {}

/**
 * Bitwise XOR
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP A GMP number resource.
 */
function gmp_xor(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Set bit
 * @param resource|string|GMP $num The number being set to. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $index The set bit.
 * @param bool $value [optional] Defines if the bit is set to 0 or 1. By default the bit is set to 1. Index starts at 0.
 * @return void No value is returned.
 */
function gmp_setbit(GMP $num, int $index, bool $value = true): void {}

/**
 * Clear bit
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $index It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return void No value is returned.
 */
function gmp_clrbit(GMP $num, int $index): void {}

/**
 * Scan for 0
 * @param resource|string|GMP $num1 The number to scan. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $start The starting bit.
 * @return int the index of the found bit, as an integer. The index starts from 0.
 */
function gmp_scan0(GMP|string|int $num1, int $start): int {}

/**
 * Scan for 1
 * @param resource|string|GMP $num1 The number to scan. It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $start The starting bit.
 * @return int the index of the found bit, as an integer. If no set bit is found, -1 is returned.
 */
function gmp_scan1(GMP|string|int $num1, int $start): int {}

/**
 * Tests if a bit is set
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @param int $index The bit to test
 * @return bool TRUE on success or FALSE on failure.
 */
function gmp_testbit(GMP|string|int $num, int $index): bool {}

/**
 * Population count
 * @param resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return int The population count of a, as an integer.
 */
function gmp_popcount(GMP|string|int $num): int {}

/**
 * Hamming distance
 * @param resource|string|GMP $num1 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number. It should be positive.
 * @param resource|string|GMP $num2 It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number. It should be positive.
 * @return int A GMP number resource.
 */
function gmp_hamdist(GMP|string|int $num1, GMP|string|int $num2): int {}

/**
 * Import from a binary string
 * @param string $data The binary string being imported
 * @param int $word_size Default value is 1. The number of bytes in each chunk of binary data. This is mainly used in conjunction with the options parameter.
 * @param int $flags Default value is GMP_MSW_FIRST | GMP_NATIVE_ENDIAN.
 * @return GMP|false Returns a GMP number or FALSE on failure.
 * @since 5.6
 */
function gmp_import(string $data, int $word_size = 1, int $flags = GMP_MSW_FIRST|GMP_NATIVE_ENDIAN): GMP {}

/**
 * Export to a binary string
 * @param GMP|string|int $num The GMP number being exported
 * @param int $word_size Default value is 1. The number of bytes in each chunk of binary data. This is mainly used in conjunction with the options parameter.
 * @param int $flags Default value is GMP_MSW_FIRST | GMP_NATIVE_ENDIAN.
 * @return string|false Returns a string or FALSE on failure.
 * @since 5.6
 */
function gmp_export(GMP|string|int $num, int $word_size = 1, int $flags = GMP_MSW_FIRST|GMP_NATIVE_ENDIAN): string {}

/**
 * Takes the nth root of a and returns the integer component of the result.
 * @param GMP|string|int $num Either a GMP number resource in PHP 5.5 and earlier, a GMP object in PHP 5.6 and later, or a numeric string provided that it is possible to convert the latter to a number.
 * @param positive-int $nth The positive root to take of a num.
 * @return GMP The integer component of the resultant root, as a GMP number.
 * @since 5.6
 */
function gmp_root(GMP|string|int $num, int $nth): GMP {}

/**
 * Takes the nth root of a and returns the integer component and remainder of the result.
 * @param GMP|string|int $num Either a GMP number resource in PHP 5.5 and earlier, a GMP object in PHP 5.6 and later, or a numeric string provided that it is possible to convert the latter to a number.
 * @param positive-int $nth The positive root to take of a num.
 * @return array|GMP[] A two element array, where the first element is the integer component of the root, and the second element is the remainder, both represented as GMP numbers.
 * @since 5.6
 */
function gmp_rootrem(GMP|string|int $num, int $nth): array {}

/**
 * Find next prime number
 * @param int|resource|string|GMP $num It can be either a GMP number resource, or a numeric string given that it is possible to convert the latter to a number.
 * @return resource|GMP Return the next prime number greater than a, as a GMP number.
 */
function gmp_nextprime(GMP|string|int $num): GMP {}

/**
 * Find previous prime number
 * @param GMP|string|int $num
 * @param bool &$definitely_prime [optional] Set to true if the result is definitely prime, false if it is only probably prime.
 * @return GMP The largest prime number less than num, as a GMP number.
 * @since 8.6
 */
function gmp_prevprime(GMP|string|int $num, &$definitely_prime = null): GMP {}

/**
 * Calculates binomial coefficient
 * @param GMP|string|int $n A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @param int $k
 * @return GMP|false Returns the binomial coefficient C(n, k).
 * @since 7.3
 * @throws \ValueError Throws ValueError if k is negative. Prior to PHP 8.0.0, E_WARNING was issued instead.
 */
function gmp_binomial(GMP|string|int $n, int $k): GMP {}

/**
 * Computes the Kronecker symbol
 * @param GMP|string|float|int $num1 A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @param GMP|string|float|int $num2 A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @return int Returns the Kronecker symbol of num1 and num2
 * @since 7.3
 */
function gmp_kronecker(GMP|string|int $num1, GMP|string|int $num2): int {}

/**
 * Computes the least common multiple of A and B
 * @param GMP|string|float|int $num1 A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @param GMP|string|float|int $num2 A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @return GMP A GMP object.
 * @since 7.3
 */
function gmp_lcm(GMP|string|int $num1, GMP|string|int $num2): GMP {}

/**
 * Perfect power check
 * @param GMP|string|float|int $num A GMP object, an integer, or a string that can be interpreted as a number following the same logic as if the string was used in gmp_init with automatic base detection (i.e. when base is equal to 0).
 * @return bool Returns true if num is a perfect power, false otherwise.
 * @since 7.3
 */
function gmp_perfect_power(GMP|string|int $num): bool {}
