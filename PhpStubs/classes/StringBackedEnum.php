<?php

/**
 * @since 8.1
 */
interface StringBackedEnum extends BackedEnum
{
    public readonly string $value;

    /**
     * Translates a string into the corresponding Enum
     * case, if any. If there is no matching case defined, it will throw a
     * ValueError.
     * @param string $value
     * @return static
     * @throws ValueError if there is no matching case defined
     */
    public static function from(string $value): static;

    /**
     * Translates a string or int into the corresponding Enum
     * case, if any. If there is no matching case defined, it will return null.
     * @param string $value
     * @return static|null
     */
    public static function tryFrom(string $value): ?static;
}
