<?php

/**
 * @since 7.2
 */
final class HashContext
{
    /**
     * Private constructor to disallow direct instantiation
     */
    private function __construct() {}

    /**
     * Serializes the HashContext object
     * @return array
     */
    public function __serialize(): array {}

    /**
     * Deserializes the data parameter into a HashContext object
     * @param array $data The value being deserialized.
     */
    public function __unserialize(array $data): void {}

    /**
     * Returns debugging information about the hashing context
     *
     * This method is not meant to be called directly; it is invoked by var_dump and related
     * functions when inspecting a HashContext instance.
     * @since 8.4
     */
    public function __debugInfo(): array {}
}
