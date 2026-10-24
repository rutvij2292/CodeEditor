<?php
namespace Random;

use Error;
use Exception;

/**
 * Provides a high-level API to the randomness provided by an Random\Engine.
 * @since 8.2
 */
final class Randomizer
{
    public readonly Engine $engine;

    /**
     * Constructs a new Randomizer
     * @param Engine|null $engine The Random\Engine to use to generate randomness. If engine is omitted or null, a new Random\Engine\Secure object will be used.
     */
    public function __construct(?Engine $engine = null) {}

    /**
     * Get a positive integer
     * @return int A positive integer between 0 and a maximum value depending on the number of bytes returned from Random\Engine::generate. The exact maximum can be calculated as 2$engine_bytes * 8 - 1 - 1.
     * @throws \Random\RandomException To avoid inconsistencies, 32 bit PHP will throw Random\RandomException if the output size of Random\Engine::generate exceeds 32 bits, as the selected integer cannot be returned losslessly. This affects the native 64 bit engines Random\Engine\PcgOneseq128XslRr64 and ...
     */
    public function nextInt(): int {}

    /**
     * Get a uniformly selected integer
     * @param int $min The lowest value to be returned.
     * @param int $max The highest value to be returned.
     * @return int A uniformly selected integer from the closed interval [min, max]. Both min and max are possible return values.
     * @throws \ValueError If max is less than min, a ValueError will be thrown. Any Throwables thrown by the Random\Engine::generate method of the underlying Random\Randomizer::$engine.
     */
    public function getInt(int $min, int $max): int {}

    /**
     * Get random bytes
     *
     * Generates a string containing uniformly selected random bytes with the requested length.
     * @param int $length The length of the random string that should be returned in bytes; must be 1 or greater.
     * @return string A string containing the requested number of random bytes.
     * @throws \ValueError If the value of length is less than 1, a ValueError will be thrown. Any Throwables thrown by the Random\Engine::generate method of the underlying Random\Randomizer::$engine.
     */
    public function getBytes(int $length): string {}

    /**
     * Get a permutation of an array
     *
     * Returns a uniformly selected permutation of the input array.
     * @param array $array The array whose values are shuffled. The input array will not be modified.
     * @return array A permutation of the values of array. Array keys of the input array will not be preserved; the returned array will be a list (array_is_list).
     */
    public function shuffleArray(array $array): array {}

    /**
     * Get a byte-wise permutation of a string
     *
     * Returns a uniformly selected permutation of the input bytes.
     * @param string $bytes The string whose bytes are shuffled. The input string will not be modified.
     * @return string A permutation of the bytes of bytes.
     */
    public function shuffleBytes(string $bytes): string {}

    /**
     * Select random array keys
     *
     * Uniformly selects num distinct array keys of the input array.
     * @param array $array The array whose array keys are selected.
     * @param int $num The number of array keys to return; must be between 1 and the number of elements in array.
     * @return array An array containing num distinct array keys of array. The returned array will be a list (array_is_list). It will be a subset of the array returned by array_keys.
     * @throws \ValueError If num is less than 1 or greater than the number of elements in array, a ValueError will be thrown. Any Throwables thrown by the Random\Engine::generate method of the underlying Random\Randomizer::$engine.
     */
    public function pickArrayKeys(array $array, int $num): array {}

    /**
     * Serializes the Randomizer object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into a Randomizer object
     * @param array $data
     * @return void No value is returned.
     */
    public function __unserialize(array $data): void {}

    /**
     * Get a float from the right-open interval [0.0, 1.0)
     *
     * Returns a uniformly selected, equidistributed float from the right-open interval from 0.0
     * until, but not including, 1.0.
     * @since 8.3
     */
    public function nextFloat(): float {}

    /**
     * Get a uniformly selected float
     *
     * Returns a uniformly selected, equidistributed float from a requested interval.
     * @since 8.3
     * @throws \ValueError If the value of min is not finite (is_finite), a ValueError will be thrown. If the value of max is not finite (is_finite), a ValueError will be thrown. If the requested interval does not contain any values, a ValueError will be thrown. Any Throwables thrown by the ...
     */
    public function getFloat(float $min, float $max, IntervalBoundary $boundary = IntervalBoundary::ClosedOpen): float {}

    /**
     * Get random bytes from a source string
     *
     * Generates a string containing uniformly selected random bytes from the input string with
     * the requested length.
     * @since 8.3
     * @throws \ValueError If string is empty, a ValueError will be thrown. If the value of length is less than 1, a ValueError will be thrown. Any Throwables thrown by the Random\Engine::generate method of the underlying Random\Randomizer::$engine.
     */
    public function getBytesFromString(string $string, int $length): string {}
}
