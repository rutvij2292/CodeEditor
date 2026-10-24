<?php

/**
 * The SensitiveParameterValue class allows wrapping sensitive values to protect them against
 * accidental exposure.
 *
 * Values of parameters having the SensitiveParameter attribute will automatically be wrapped inside
 * of a SensitiveParameterValue object within stack traces.
 * @since 8.2
 */
final class SensitiveParameterValue
{
    private readonly mixed $value;

    /**
     * Constructs a new SensitiveParameterValue object
     *
     * Construct a SensitiveParameterValue holding a sensitive value.
     * @param mixed $value An arbitrary value that should be stored inside the SensitiveParameterValue object.
     */
    public function __construct(mixed $value) {}

    /**
     * Returns the sensitive value
     *
     * Get the sensitive value.
     * @return mixed The sensitive value.
     */
    public function getValue(): mixed {}

    /**
     * Protects the sensitive value against accidental exposure
     *
     * Returns an empty array to protect the sensitive value against accidental exposure when using
     * var_dump.
     * @return array An empty array.
     */
    public function __debugInfo(): array {}
}
