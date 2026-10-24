<?php

/**
 * The ReflectionObject class reports
 * information about an object.
 */
class ReflectionObject extends ReflectionClass
{
    /**
     * Constructs a ReflectionObject
     * @param object $object An object instance.
     */
    public function __construct(object $object) {}

    /**
     * Export
     * @param string $argument The reflection to export.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($argument, $return = false) {}
}
