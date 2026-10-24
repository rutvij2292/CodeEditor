<?php

/**
 * A fully opaque class which replaces OpenSSL key resources as of PHP 8.0.0.
 * @since 8.0
 */
final class OpenSSLAsymmetricKey
{
    /**
     * Cannot directly construct OpenSSLAsymmetricKey, use openssl_pkey_new() instead
     * @see openssl_pkey_new()
     */
    private function __construct() {}
}
