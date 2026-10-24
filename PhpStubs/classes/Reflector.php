<?php

/**
 * Reflector is an interface implemented by all
 * exportable Reflection classes.
 */
interface Reflector extends Stringable
{
    /**
     * Exports a class.
     * @return string|null
     * @removed 7.4
     */
    public static function export();

    /**
     * Returns the string representation of any Reflection object.
     *
     * Please note that since PHP 8.0 this method is absent in this interface
     * and inherits from the Stringable parent.
     * @return string
     */
    public function __toString(): string;
}
