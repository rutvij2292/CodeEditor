<?php

/**
 * The reflection class.
 */
class Reflection
{
    /**
     * Gets modifier names
     * @param int $modifiers Bitfield of the modifiers to get.
     * @return string[] An array of modifier names.
     */
    public static function getModifierNames(int $modifiers): array {}

    /**
     * Exports
     * @param Reflector $reflector The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export(Reflector $reflector, $return = false) {}
}
