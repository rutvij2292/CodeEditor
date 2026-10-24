<?php

/**
 * The ReflectionEnum class reports information about an Enum.
 * @since 8.1
 */
class ReflectionEnum extends ReflectionClass
{
    /**
     * Instantiates a ReflectionEnum object
     * @param object|string $objectOrClass An enum instance or a name.
     * @throws ReflectionException if the class does not exist.
     */
    public function __construct(object|string $objectOrClass) {}

    /**
     * Checks for a case on an Enum
     *
     * Determines if a given case is defined on an Enum.
     * @param string $name The case to check for.
     * @return bool true if the case is defined, false if not.
     */
    public function hasCase(string $name): bool {}

    /**
     * Returns a list of all cases on an Enum
     *
     * An Enum may contain zero or more cases. This method retrieves all defined cases, in lexical
     * order (that is, the order they appear in the source code).
     * @return ReflectionEnumUnitCase[]|ReflectionEnumBackedCase[] An array of Enum reflection objects, one for each case in the Enum. For a Unit Enum, they will all be instances of ReflectionEnumUnitCase. For a Backed Enum, they will all be instances of ReflectionEnumBackedCase.
     */
    public function getCases(): array {}

    /**
     * Returns a specific case of an Enum
     *
     * Returns the reflection object for a specific Enum case by name. If the requested case is not
     * defined, a ReflectionException is thrown.
     * @return ReflectionEnumUnitCase|ReflectionEnumBackedCase An instance of ReflectionEnumUnitCase or ReflectionEnumBackedCase, as appropriate.
     * @throws ReflectionException If no found single reflection object for the corresponding case
     */
    public function getCase(string $name): ReflectionEnumUnitCase {}

    /**
     * Determines if an Enum is a Backed Enum
     *
     * A Backed Enum is one that has a native backing scalar equivalent, either a string or an int.
     * Not all Enums are backed.
     * @return bool true if the Enum has a backing scalar, false if not.
     */
    public function isBacked(): bool {}

    /**
     * Gets the backing type of an Enum, if any
     *
     * If the enumeration is a Backed Enum, this method will return an instance of ReflectionType
     * for the backing type of the Enum. If it is not a Backed Enum, it will return null.
     * @return ReflectionType|null An instance of ReflectionNamedType, or null if the Enum has no backing type.
     */
    public function getBackingType(): null|ReflectionNamedType {}
}
