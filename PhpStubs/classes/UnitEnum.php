<?php

/**
 * The UnitEnum interface is automatically applied to all enumerations by the engine. It may not be
 * implemented by user-defined classes. Enumerations may not override its methods, as default
 * implementations are provided by the engine. It is available only for type checks.
 * @since 8.1
 */
interface UnitEnum
{
    public readonly string $name;

    /**
     * Generates a list of cases on an enum
     *
     * This method will return a packed array of all cases in an enumeration, in order of
     * declaration.
     * @return static[] An array of all defined cases of this enumeration, in order of declaration.
     */
    public static function cases(): array;
}
