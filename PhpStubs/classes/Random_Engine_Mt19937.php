<?php
namespace Random\Engine;

use const MT_RAND_MT19937;

/**
 * Implements the Mt19937 (“Mersenne Twister”) algorithm.
 * @since 8.2
 */
final class Mt19937 implements \Random\Engine
{
    /**
     * Constructs a new Mt19937 engine
     * @param int|null $seed Fills the state with values generated with a linear congruential generator that was seeded with seed interpreted as an unsigned 32 bit integer. If seed is omitted or null, a random unsigned 32 bit integer will be used.
     * @param int $mode Use one of the following constants to specify the implementation of the algorithm to use. MT_RAND_MT19937: The correct Mt19937 implementation. MT_RAND_PHP: An incorrect implementation for backwards compatibility with mt_srand prior to PHP 7.1.0. This feature has been DEPRECATED as ...
     */
    public function __construct(int|null $seed = null, int $mode = MT_RAND_MT19937) {}

    /**
     * Generate 32 bits of randomness
     * @return string A string representing an unsigned 32 bit integer in little-endian order.
     */
    public function generate(): string {}

    /**
     * Serializes the Mt19937 object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into a Mt19937 object
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
