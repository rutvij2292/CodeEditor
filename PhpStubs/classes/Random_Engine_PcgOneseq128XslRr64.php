<?php
namespace Random\Engine;

use const MT_RAND_MT19937;

/**
 * Implements a Permuted congruential generator (PCG) with 128 bits of state, XSL and RR output
 * transformations, and 64 bits of output.
 * @since 8.2
 */
final class PcgOneseq128XslRr64 implements \Random\Engine
{
    /**
     * Constructs a new PCG Oneseq 128 XSL RR 64 engine
     * @param string|int|null $seed How the internal 128 bit (16 byte) state consisting of one unsigned 128 bit integer is seeded depends on the type used as the seed. Type Description null Fills the state with 16 random bytes generated using the CSPRNG. int Fills the state by setting the state to 0, ...
     * @throws \ValueError If the length of a string seed is not 16 bytes, a ValueError will be thrown.
     */
    public function __construct(string|int|null $seed = null) {}

    /**
     * Generate 64 bits of randomness
     * @return string A string representing an unsigned 64 bit integer in little-endian order.
     */
    public function generate(): string {}

    /**
     * Efficiently move the engine ahead multiple steps
     *
     * Moves the algorithm’s state ahead by the number of steps given by advance, as if
     * Random\Engine\PcgOneseq128XslRr64::generate was called that many times.
     * @param int $advance The number of steps to move ahead; must be 0 or greater.
     * @return void No value is returned.
     * @throws \ValueError If advance is less than 0, a ValueError will be thrown.
     */
    public function jump(int $advance): void {}

    /**
     * Serializes the PcgOneseq128XslRr64 object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into a PcgOneseq128XslRr64 object
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
