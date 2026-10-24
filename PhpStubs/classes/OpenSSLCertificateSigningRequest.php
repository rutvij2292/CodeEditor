<?php

/**
 * A fully opaque class which replaces OpenSSL X.509 CSR resources as of PHP 8.0.0.
 * @since 8.0
 */
final class OpenSSLCertificateSigningRequest
{
    /**
     * Cannot directly construct OpenSSLCertificateSigningRequest, use openssl_csr_new() instead
     * @see openssl_csr_new()
     */
    private function __construct() {}
}
