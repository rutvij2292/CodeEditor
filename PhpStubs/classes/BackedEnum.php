<?php

/**
 * The BackedEnum interface is automatically applied to backed enumerations by the engine. It may
 * not be implemented by user-defined classes. Enumerations may not override its methods, as default
 * implementations are provided by the engine. It is available only for type checks.
 * @since 8.1
 */
interface BackedEnum extends UnitEnum
{
    public readonly int|string $value;

    /**
     * Translates a string or int into the corresponding Enum
     * case, if any. If there is no matching case defined, it will throw a
     * ValueError.
     * @param int|string $value The scalar value to map to an enum case.
     * @throws ValueError if there is no matching case defined
     * @throws TypeError
     * @return static A case instance of this enumeration.
     */
    public static function from(int|string $value): static;

    /**
     * Translates a string or int into the corresponding Enum
     * case, if any. If there is no matching case defined, it will return null.
     * @param int|string $value The scalar value to map to an enum case.
     * @return static|null A case instance of this enumeration, or null if not found.
     */
    public static function tryFrom(int|string $value): ?static;
}
