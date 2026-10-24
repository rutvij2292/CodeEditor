<?php

/**
 * The ReflectionType class reports information about a function's parameters.
 * @since 7.0
 */
abstract class ReflectionType implements Stringable
{
    /**
     * Checks if null is allowed
     * @return bool Returns true if null is allowed, otherwise false
     * @since 7.0
     */
    public function allowsNull(): bool {}

    /**
     * Checks if it is a built-in type
     * @return bool Returns true if it's a built-in type, otherwise false
     * @since 7.0
     * @removed 8.0 this method has been removed from the ReflectionType class and moved to the ReflectionNamedType child.
     */
    public function isBuiltin() {}

    /**
     * To string
     * @return string Returns the type of the parameter.
     * @since 7.0
     * @see ReflectionNamedType::getName()
     */
    public function __toString(): string {}

    /**
     * Cloning of this class is prohibited
     * @return void
     */
    private function __clone(): void {}
}
