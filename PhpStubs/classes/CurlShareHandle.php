<?php

/**
 * A fully opaque class which replaces curl_share resources as of PHP 8.0.0.
 * @since 8.0
 */
final class CurlShareHandle
{
    /**
     * Cannot directly construct CurlShareHandle, use curl_share_init() instead
     * @see  curl_share_init()
     */
    private function __construct() {}
}
