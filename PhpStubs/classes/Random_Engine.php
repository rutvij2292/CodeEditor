<?php
namespace Random;

use Error;
use Exception;

/**
 * A Random\Engine provides a low-level source of randomness by returning random bytes that are
 * consumed by high-level APIs to perform their operations. The Random\Engine interface allows
 * swapping out the algorithm used to generate randomness, because each algorithm makes
 * different tradeoffs to fit specific use-cases. Some algorithms are very fast, but generate
 * lower-quality randomness, whereas other algorithms are slower, but generate better
 * randomness, up to cryptographically secure randomness as provided by the Random\Engine\Secure
 * engine.
 *
 * PHP provides several Random\Engines out of the box to accommodate different use-cases. The
 * Random\Engine\Secure engine that is backed by a CSPRNG is the ...
 * @since 8.2
 */
interface Engine
{
    /**
     * Generates randomness
     *
     * Returns randomness and advances the algorithm’s state by one step.
     * @return string A non-empty string containing random bytes. The Random\Randomizer works with unsigned 64 bit integers internally. If the returned string contains more than 64 bit (8 byte) of randomness the exceeding bytes will be ignored. Other applications may be able to process more than 64 bit at ...
     * @throws \Random\RandomException If generating randomness fails, a Random\RandomException should be thrown. Any other Exception thrown during generation should be caught and wrapped into a Random\RandomException.
     * @throws \Random\BrokenRandomEngineError If generating randomness fails, a Random\RandomException should be thrown. Any other Exception thrown during generation should be caught and wrapped into a Random\RandomException. If the returned string is empty, a Random\BrokenRandomEngineError will be ...
     */
    public function generate(): string;
}
