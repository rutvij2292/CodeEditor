<?php

/**
 * A fully opaque class which replaces AddressInfo resources as of PHP 8.0.0.
 * @since 8.0
 */
final class AddressInfo
{
    /**
     * Cannot directly construct AddressInfo, use socket_addrinfo_lookup() instead
     * @see socket_addrinfo_lookup()
     */
    private function __construct() {}
}
