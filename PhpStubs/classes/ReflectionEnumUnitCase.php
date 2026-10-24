<?php

/**
 * The ReflectionEnumUnitCase class reports information about an Enum unit case, which has no scalar
 * equivalent.
 * @since 8.1
 */
class ReflectionEnumUnitCase extends ReflectionClassConstant
{
    /**
     * Instantiates a ReflectionEnumUnitCase object
     * @param object|string $class An enum instance or a name.
     * @param string $constant An enum constant name.
     */
    public function __construct(object|string $class, string $constant) {}

    /**
     * Gets the enum case object described by this reflection object
     *
     * Returns the enum case object described by this reflection object.
     * @return UnitEnum The enum case object described by this reflection object.
     */
    public function getValue(): UnitEnum {}

    /**
     * Gets the reflection of the enum of this case
     * @return ReflectionEnum A ReflectionEnum instance describing the Enum this case belongs to.
     */
    public function getEnum(): ReflectionEnum {}
}
