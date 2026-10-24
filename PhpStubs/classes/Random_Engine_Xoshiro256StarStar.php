<?php
namespace Random\Engine;

use const MT_RAND_MT19937;

/**
 * Implements the xoshiro256** algorithm.
 * @since 8.2
 */
final class Xoshiro256StarStar implements \Random\Engine
{
    /**
     * Constructs a new xoshiro256** engine
     * @param string|int|null $seed How the internal 256 bit (32 byte) state consisting of four unsigned 64 bit integers is seeded depends on the type used as the seed. Type Description null Fills the state with 32 random bytes generated using the CSPRNG. int Fills the state with four consecutive values ...
     * @throws \ValueError If the length of a string seed is not 32 bytes, a ValueError will be thrown. If a string seed consists of 32 NUL bytes ("\x00"), a ValueError will be thrown.
     */
    public function __construct(string|int|null $seed = null) {}

    /**
     * Generate 64 bits of randomness
     * @return string A string representing an unsigned 64 bit integer in little-endian order.
     */
    public function generate(): string {}

    /**
     * Efficiently move the engine ahead by 2^128 steps
     *
     * Moves the algorithm’s state ahead by 2128 steps, as if
     * Random\Engine\Xoshiro256StarStar::generate was called 2128 times.
     * @return void No value is returned.
     */
    public function jump(): void {}

    /**
     * Efficiently move the engine ahead by 2^192 steps
     *
     * Moves the algorithm’s state ahead by 2192 steps, as if
     * Random\Engine\Xoshiro256StarStar::generate was called 2192 times.
     * @return void No value is returned.
     */
    public function jumpLong(): void {}

    /**
     * Serializes the Xoshiro256StarStar object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into a Xoshiro256StarStar object
     * @param array $data
     * @return void No value is returned.
     */
    public function __unserialize(array $data): void {}

    /**
     * Returns the internal state of the engine
     * @return array
     */
    public function __debugInfo(): array {}
}
