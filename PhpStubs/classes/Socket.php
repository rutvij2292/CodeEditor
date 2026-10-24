<?php

/**
 * A fully opaque class which replaces Socket resources as of PHP 8.0.0.
 * @since 8.0
 */
final class Socket
{
    /**
     * Cannot directly construct Socket, use socket_create() instead
     * @see socket_create()
     */
    private function __construct() {}
}
