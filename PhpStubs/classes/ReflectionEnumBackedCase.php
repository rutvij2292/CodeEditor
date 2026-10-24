<?php

/**
 * The ReflectionEnumBackedCase class reports information about an Enum backed case, which has a
 * scalar equivalent.
 * @since 8.1
 */
class ReflectionEnumBackedCase extends ReflectionEnumUnitCase
{
    /**
     * Instantiates a ReflectionEnumBackedCase object
     * @param object|string $class An enum instance or a name.
     * @param string $constant An enum constant name.
     */
    public function __construct(object|string $class, string $constant) {}

    /**
     * Gets the scalar value backing this Enum case
     * @return int|string The scalar equivalent of this enum case.
     */
    public function getBackingValue(): int|string {}
}
