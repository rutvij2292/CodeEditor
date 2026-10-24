<?php

/**
 * A fully opaque class which replaces OpenSSL X.509 resources as of PHP 8.0.0.
 * @since 8.0
 */
final class OpenSSLCertificate
{
    /**
     * Cannot directly construct OpenSSLCertificate, use openssl_x509_read() instead
     * @see openssl_x509_read()
     */
    private function __construct() {}
}
