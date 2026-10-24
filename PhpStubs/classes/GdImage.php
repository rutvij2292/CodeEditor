<?php

/**
 * A fully opaque class which replaces gd resources as of PHP 8.0.0.
 * @since 8.0
 */
final class GdImage
{
    /**
     * You cannot initialize a GdImage object except through helper functions.
     */
    private function __construct() {}

    private function __clone() {}
}
