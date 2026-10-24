<?php

/**
 * @since 8.0
 */
class ReflectionUnionType extends ReflectionType
{
    /**
     * Get list of types of union type
     * @return ReflectionNamedType[]|ReflectionIntersectionType[] An array of ReflectionType objects.
     */
    public function getTypes(): array {}
}
