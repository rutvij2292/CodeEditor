<?php

/**
 * @since 7.1
 */
class ReflectionNamedType extends ReflectionType
{
    /**
     * Get the text of the type hint.
     * @return string Returns the text of the type hint.
     * @since 7.1
     */
    public function getName(): string {}

    /**
     * Checks if it is a built-in type
     * @return bool Returns true if it's a built-in type, otherwise false
     * @since 7.1 overrides the parent ReflectionType::isBuiltin() method.
     * @since 8.0 method was removed from the parent ReflectionType class.
     */
    public function isBuiltin(): bool {}
}
