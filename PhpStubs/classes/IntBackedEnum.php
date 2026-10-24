<?php

/**
 * @since 8.1
 */
interface IntBackedEnum extends BackedEnum
{
    public readonly int $value;

    /**
     * Translates an int into the corresponding Enum
     * case, if any. If there is no matching case defined, it will throw a
     * ValueError.
     * @param int $value
     * @return static
     * @throws ValueError if there is no matching case defined
     */
    public static function from(int $value): static;

    /**
     * Translates an int into the corresponding Enum
     * case, if any. If there is no matching case defined, it will return null.
     * @param int $value
     * @return static|null
     */
    public static function tryFrom(int $value): ?static;
}
