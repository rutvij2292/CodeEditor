<?php

/**
 * @since 8.1
 */
final class FiberError extends Error
{
    /**
     * Constructor to disallow direct instantiation
     * @throws \Error Throws an Error exception when called.
     */
    public function __construct() {}
}
