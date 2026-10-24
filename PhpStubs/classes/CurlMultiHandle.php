<?php

/**
 * A fully opaque class which replaces curl_multi resources as of PHP 8.0.0.
 * @since 8.0
 */
final class CurlMultiHandle
{
    /**
     * Cannot directly construct CurlMultiHandle, use curl_multi_init() instead
     * @see curl_multi_init()
     */
    private function __construct() {}
}
