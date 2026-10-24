<?php
namespace BcMath;

/**
 * A class for an arbitrary precision number. These objects support overloaded arithmetic and
 * comparison operators.
 * @since 8.4
 */
final readonly class Number implements \Stringable
{
    /**
     * @var numeric-string
     */
    public readonly string $value;

    public readonly int $scale;

    /**
     * Creates a BcMath\Number object
     *
     * Creates a BcMath\Number object from an int or string value.
     * @param int|numeric-string $num An int or string value. If num is a int, the BcMath\Number::scale is always set to 0. If num is a string, it must be a valid number, and the BcMath\Number::scale is automatically set by parsing the string.
     * @throws \ValueError
     */
    public function __construct(string|int $num) {}

    /**
     * Adds an arbitrary precision number
     *
     * Adds $this and num.
     * @param Number|int|numeric-string $num The value to add.
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \ValueError
     */
    public function add(Number|string|int $num, ?int $scale = null): Number {}

    /**
     * Subtracts an arbitrary precision number
     *
     * Subtracts num from $this.
     * @param Number|int|numeric-string $num The value to subtract.
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \ValueError
     */
    public function sub(Number|string|int $num, ?int $scale = null): Number {}

    /**
     * Multiplies an arbitrary precision number
     *
     * Multiplies $this by num.
     * @param Number|int|numeric-string $num The multiplier.
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \ValueError
     */
    public function mul(Number|string|int $num, ?int $scale = null): Number {}

    /**
     * Divides by an arbitrary precision number
     *
     * Divides $this by num.
     * @param Number|int|numeric-string $num The divisor.
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \DivisionByZeroError
     * @throws \ValueError
     */
    public function div(Number|string|int $num, ?int $scale = null): Number {}

    /**
     * Gets the modulus of an arbitrary precision number
     *
     * Gets the remainder of dividing $this by num. Unless num is 0, the result has the same
     * sign as $this.
     * @param Number|int|numeric-string $num The divisor.
     * @param int|null $scale
     * @throws \DivisionByZeroError
     * @throws \ValueError
     */
    public function mod(Number|string|int $num, ?int $scale = null): Number {}

    /**
     * Gets the quotient and modulus of an arbitrary precision number
     *
     * Gets the quotient and remainder of dividing $this by num.
     * @param Number|int|numeric-string $num The divisor.
     * @param int|null $scale
     * @return array{Number, Number} Returns an indexed array where the first element is the quotient as a new BcMath\Number object and the second element is the remainder as a new BcMath\Number object. The quotient is always an integer value, so BcMath\Number::scale of the quotient will always be 0, ...
     * @throws \DivisionByZeroError
     * @throws \ValueError
     */
    public function divmod(Number|string|int $num, ?int $scale = null): array {}

    /**
     * Raises an arbitrary precision number, reduced by a specified modulus
     *
     * Use the fast-exponentiation method to raise $this to the power exponent with respect to
     * the modulus modulus.
     * @param Number|int|numeric-string $exponent The exponent, as an non-negative and integral (i.e. the scale has to be zero).
     * @param Number|int|numeric-string $modulus The modulus, as an integral (i.e. the scale has to be zero).
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \DivisionByZeroError
     * @throws \ValueError
     */
    public function powmod(Number|string|int $exponent, Number|string|int $modulus, ?int $scale = null): Number {}

    /**
     * Raises an arbitrary precision number
     *
     * Raises $this to the exponent power.
     * @param Number|int|numeric-string $exponent The exponent. Must be a value with no fractional part. The valid range of the exponent is platform specific, but it is at least -2147483648 to 2147483647.
     * @param int|null $scale BcMath\Number::scale explicitly specified for calculation results. If null, the BcMath\Number::scale of the calculation result will be set automatically.
     * @throws \DivisionByZeroError
     * @throws \ValueError
     */
    public function pow(Number|string|int $exponent, ?int $scale = null): Number {}

    /**
     * Gets the square root of an arbitrary precision number
     *
     * Return the square root of $this.
     * @throws \ValueError
     */
    public function sqrt(?int $scale = null): Number {}

    /**
     * Rounds down an arbitrary precision number
     *
     * Returns the next highest integer value by rounding down $this if necessary.
     * @return Number Returns the result as a new BcMath\Number object. The BcMath\Number::scale of the result is always 0.
     */
    public function floor(): Number {}

    /**
     * Rounds up an arbitrary precision number
     *
     * Returns the next highest integer value by rounding up $this if necessary.
     * @return Number Returns the result as a new BcMath\Number object. The BcMath\Number::scale of the result is always 0.
     */
    public function ceil(): Number {}

    /**
     * Rounds an arbitrary precision number
     *
     * Returns the rounded value of $this to specified precision (number of digits after the
     * decimal point). precision can also be negative or zero (default).
     * @throws \ValueError
     */
    public function round(int $precision = 0, \RoundingMode $mode = \RoundingMode::HalfAwayFromZero): Number {}

    /**
     * Compares two arbitrary precision numbers
     *
     * Compare two arbitrary precision numbers. This method behaves similar to the spaceship
     * operator.
     * @param Number|int|numeric-string $num The value to be compared to.
     * @param int|null $scale Specify the scale to use for comparison. If null, all digits are used in the comparison.
     * @return int Returns -1, 0, or 1
     * @throws \ValueError
     */
    public function compare(Number|string|int $num, ?int $scale = null): int {}

    /**
     * Converts BcMath\Number to string
     * @return string Returns BcMath\Number::value as a string.
     */
    public function __toString(): string {}

    /**
     * Serializes a BcMath\Number object
     *
     * Serializes $this.
     * @return array{value:numeric-string}
     */
    public function __serialize(): array {}

    /**
     * Deserializes a data parameter into a BcMath\Number object
     * @param array{value:numeric-string} $data The serialized data parameter as an associative array
     * @throws \ValueError This method throws a ValueError if invalid serialized data is passed.
     */
    public function __unserialize(array $data): void {}
}
