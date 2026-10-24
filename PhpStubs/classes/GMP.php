<?php

/**
 * A GMP number. These objects support overloaded arithmetic, bitwise and comparison operators.
 */
final class GMP
{
    /**
     * Create GMP number
     *
     * Creates a GMP number from an integer or string.
     * @since 8.2
     */
    public function __construct(int|string $num = 0, int $base = 0) {}

    /**
     * Get array representation of object
     * @return array The array representation of the GMP object.
     */
    public function __serialize(): array {}

    /**
     * Reconstructs the GMP object from array representation
     * @param array $data The array representation of the GMP object.
     * @return void
     */
    public function __unserialize(array $data): void {}
}
