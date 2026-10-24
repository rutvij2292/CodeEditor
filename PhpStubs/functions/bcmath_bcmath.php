<?php

/**
 * Add two arbitrary precision numbers
 * @param string $num1 The left operand, as a string.
 * @param string $num2 The right operand, as a string.
 * @param int|null $scale This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string The sum of the two operands, as a string.
 * @throws \ValueError This function throws a ValueError in the following cases: num1 or num2 is not a well-formed BCMath numeric string. scale is outside the valid range.
 */
function bcadd(string $num1, string $num2, ?int $scale = null): string {}

/**
 * Subtract one arbitrary precision number from another
 * @param string $num1 The left operand, as a string.
 * @param string $num2 The right operand, as a string.
 * @param int|null $scale This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string The result of the subtraction, as a string.
 */
function bcsub(string $num1, string $num2, ?int $scale = null): string {}

/**
 * Multiply two arbitrary precision numbers
 * @param string $num1 The left operand, as a string.
 * @param string $num2 The right operand, as a string.
 * @param int|null $scale This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string the result as a string.
 */
function bcmul(string $num1, string $num2, ?int $scale = null): string {}

/**
 * Divide two arbitrary precision numbers
 * @param string $num1 The dividend, as a string.
 * @param string $num2 The divisor, as a string.
 * @param int|null $scale [optional] This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string the result of the division as a string.
 * @throws \DivisionByZeroError if divisor is 0. Available since PHP 8.0.
 */
function bcdiv(string $num1, string $num2, ?int $scale = null): string {}

/**
 * Get modulus of an arbitrary precision number
 * @param string $num1 The dividend, as a string. Since PHP 7.2, the divided is no longer truncated to an integer.
 * @param string $num2 The divisor, as a string. Since PHP 7.2, the divisor is no longer truncated to an integer.
 * @param int|null $scale [optional] This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set. Available since PHP 7.2.
 * @return string the modulus as a string.
 * @throws \DivisionByZeroError if divisor is 0. Available since PHP 8.0.
 */
function bcmod(string $num1, string $num2, ?int $scale = null): string {}

/**
 * Raise an arbitrary precision number to another
 * @param string $num The base, as a string.
 * @param string $exponent The exponent, as a string. If the exponent is non-integral, it is truncated. The valid range of the exponent is platform specific, but is at least -2147483648 to 2147483647.
 * @param int|null $scale This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string the result as a string.
 * @throws \ValueError This function throws a ValueError in the following cases: num or exponent is not a well-formed BCMath numeric string; exponent has a fractional part; exponent or scale is outside the valid range
 * @throws \DivisionByZeroError This function throws a DivisionByZeroError exception if num is 0 and exponent is a negative value.
 */
function bcpow(string $num, string $exponent, ?int $scale = null): string {}

/**
 * Get the square root of an arbitrary precision number
 * @param string $num The operand, as a string.
 * @param int|null $scale [optional]
 * @return string|null the square root as a string, or NULL if operand is negative.
 * @throws \ValueError This function throws a ValueError in the following cases: num is not a well-formed BCMath numeric string; num is less than 0; scale is outside the valid range
 */
function bcsqrt(string $num, ?int $scale = null): string {}

/**
 * Set default scale parameter for all bc math functions
 * @param int $scale The scale factor.
 * @return int|bool Returns the old scale when used as setter. Otherwise the current scale is returned.
 * @throws \ValueError This function throws a ValueError if scale is outside the valid range.
 */
function bcscale(
        int|null $scale = null
    ): int {}

/**
 * Compare two arbitrary precision numbers
 * @param string $num1 The left operand, as a string.
 * @param string $num2 The right operand, as a string.
 * @param int|null $scale The optional scale parameter is used to set the number of digits after the decimal place which will be used in the comparison.
 * @return int 0 if the two operands are equal, 1 if the left_operand is larger than the right_operand, -1 otherwise.
 */
function bccomp(string $num1, string $num2, ?int $scale = null): int {}

/**
 * Raise an arbitrary precision number to another, reduced by a specified modulus
 * @param string $num The base, as an integral string (i.e. the scale has to be zero).
 * @param string $exponent The exponent, as an non-negative, integral string (i.e. the scale has to be zero).
 * @param string $modulus The modulus, as an integral string (i.e. the scale has to be zero).
 * @param int|null $scale This optional parameter is used to set the number of digits after the decimal place in the result. If omitted, it will default to the scale set globally with the bcscale() function, or fallback to 0 if this has not been set.
 * @return string|null the result as a string, or NULL if modulus is 0 or exponent is negative.
 * @throws \ValueError This function throws a ValueError in the following cases: num, exponent or modulus is not a well-formed BCMath numeric string; num, exponent or modulus has a fractional part; exponent is a negative value; scale is outside the valid range
 * @throws \DivisionByZeroError This function throws a DivisionByZeroError exception if modulus is 0.
 */
function bcpowmod(string $num, string $exponent, string $modulus, ?int $scale = null): string {}

/**
 * Round down arbitrary precision number
 *
 * Returns the next lowest integer value by rounding down num if necessary.
 * @since 8.4
 */
function bcfloor(string $num): string {}

/**
 * Round up arbitrary precision number
 *
 * Returns the next highest integer value by rounding up num if necessary.
 * @since 8.4
 * @throws \ValueError This function throws a ValueError if num is not a well-formed BCMath numeric string.
 */
function bcceil(string $num): string {}

/**
 * Round arbitrary precision number
 *
 * Returns the rounded value of num to specified precision (number of digits after the decimal
 * point). precision can also be negative or zero (default).
 * @since 8.4
 * @throws \ValueError This function throws a ValueError in the following cases: num is not a well-formed BCMath numeric string. An invalid mode is specified.
 */
function bcround(string $num, int $precision = 0, RoundingMode $mode = RoundingMode::HalfAwayFromZero): string {}

/**
 * Get the quotient and modulus of an arbitrary precision number
 *
 * Get the quotient and remainder of dividing num1 by num2.
 * @return string[] Returns an indexed array where the first element is the quotient as a string and the second element is the remainder as a string.
 */
function bcdivmod(string $num1, string $num2, ?int $scale = null): array {}
