<?php

/**
 * A fully opaque class which replaces curl resources as of PHP 8.0.0.
 * @since 8.0
 */
final class CurlHandle
{
    /**
     * Cannot directly construct CurlHandle, use curl_init() instead
     * @see curl_init()
     */
    private function __construct() {}
}
