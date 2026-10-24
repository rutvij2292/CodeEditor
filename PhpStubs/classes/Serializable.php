<?php

/**
 * Interface for customized serializing.
 *
 * As of PHP 8.1.0, a class which implements Serializable without also implementing `__serialize()` and `__unserialize()`
 * will generate a deprecation warning.
 */
interface Serializable
{
    /**
     * String representation of object.
     * @return string|null The string representation of the object or null
     * @throws Exception Returning other type than string or null
     */
    public function serialize();

    /**
     * Constructs the object.
     * @param string $data The string representation of the object.
     * @return void The return value from this method is ignored.
     */
    public function unserialize(string $data);
}
