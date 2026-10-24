<?php

/**
 * A fully opaque class which replaces zlib.deflate resources as of PHP 8.0.0.
 * @since 8.0
 */
final class DeflateContext
{
    /**
     * Use deflate_init() instead
     * @see deflate_init()
     */
    private function __construct() {}
}
