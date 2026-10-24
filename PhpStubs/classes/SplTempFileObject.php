<?php

/**
 * The SplTempFileObject class offers an object oriented interface for a temporary file.
 */
class SplTempFileObject extends SplFileObject
{
    /**
     * Construct a new temporary file object
     * @param int $maxMemory [optional]
     * @throws RuntimeException if an error occurs.
     * @since 5.1
     */
    public function __construct(int $maxMemory = 2097152) {}
}
