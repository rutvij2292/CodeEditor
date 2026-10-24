<?php

/**
 * Frees a private key
 * @param OpenSSLAsymmetricKey|resource $key Resource holding the key.
 * @return void No value is returned.
 * @deprecated
 */
function openssl_pkey_free(OpenSSLAsymmetricKey $key): void {}

/**
 * Generates a new private key
 * @param array|null $options [optional] You can finetune the key generation (such as specifying the number of bits) using configargs. See openssl_csr_new for more information about configargs.
 * @return OpenSSLAsymmetricKey|resource|false a resource identifier for the pkey on success, or false on error.
 */
function openssl_pkey_new(?array $options = null): OpenSSLAsymmetricKey|false {}

/**
 * Gets an exportable representation of a key into a string
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $key
 * @param string &$output
 * @param string|null $passphrase [optional] The key is optionally protected by passphrase.
 * @param array|null $options [optional] configargs can be used to fine-tune the export process by specifying and/or overriding options for the openssl configuration file. See openssl_csr_new for more information about configargs.
 * @return bool true on success or false on failure.
 */
function openssl_pkey_export(
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $key,
    &$output,
    ?string $passphrase = null,
    ?array $options = null
): bool {}

/**
 * Gets an exportable representation of a key into a file
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $key
 * @param string $output_filename Path to the output file.
 * @param string|null $passphrase [optional] The key can be optionally protected by a passphrase.
 * @param array|null $options [optional] configargs can be used to fine-tune the export process by specifying and/or overriding options for the openssl configuration file. See openssl_csr_new for more information about configargs.
 * @return bool true on success or false on failure.
 */
function openssl_pkey_export_to_file(
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $key,
    string $output_filename,
    ?string $passphrase = null,
    ?array $options = null
): bool {}

/**
 * Get a private key
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key key can be one of the following: a string having the format file://path/to/file.pem. The named file must contain a PEM encoded certificate/private key (it may contain both). A PEM formatted private key.
 * @param string|null $passphrase The optional parameter passphrase must be used if the specified key is encrypted (protected by a passphrase).
 * @return OpenSSLAsymmetricKey|resource|false Returns a positive key resource identifier on success, or FALSE on error.
 */
function openssl_pkey_get_private(
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    ?string $passphrase = null
): OpenSSLAsymmetricKey|false {}

/**
 * Extract public key from certificate and prepare it for use
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key certificate can be one of the following: an X.509 certificate resource a string having the format file://path/to/file.pem. The named file must contain a PEM encoded certificate/public key (it may contain both). A PEM formatted ...
 * @return OpenSSLAsymmetricKey|resource|false a positive key resource identifier on success, or false on error.
 */
function openssl_pkey_get_public(OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key): OpenSSLAsymmetricKey|false {}

/**
 * Returns an array with the key details
 * @param OpenSSLAsymmetricKey|resource $key Resource holding the key.
 * @return array|false an array with the key details in success or false in failure. Returned array has indexes bits (number of bits), key (string representation of the public key) and type (type of the key which is one of OPENSSL_KEYTYPE_RSA, OPENSSL_KEYTYPE_DSA, OPENSSL_KEYTYPE_DH, ...
 */
function openssl_pkey_get_details(OpenSSLAsymmetricKey $key): array|false {}

/**
 * Free key resource
 * @param OpenSSLAsymmetricKey|resource $key
 * @return void No value is returned.
 * @deprecated
 */
function openssl_free_key(OpenSSLAsymmetricKey $key): void {}

/**
 * Alias of openssl_pkey_get_private
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key key can be one of the following: a string having the format file://path/to/file.pem. The named file must contain a PEM encoded certificate/private key (it may contain both). A PEM formatted private key.
 * @param string|null $passphrase [optional] The optional parameter passphrase must be used if the specified key is encrypted (protected by a passphrase).
 * @return OpenSSLAsymmetricKey|resource|false Returns a positive key resource identifier on success, or FALSE on error.
 */
function openssl_get_privatekey(
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    ?string $passphrase = null
): OpenSSLAsymmetricKey|false {}

/**
 * Alias of openssl_pkey_get_public
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key certificate can be one of the following: an X.509 certificate resource a string having the format file://path/to/file.pem. The named file must contain a PEM encoded certificate/public key (it may contain both). A PEM formatted ...
 * @return OpenSSLAsymmetricKey|false a positive key resource identifier on success, or FALSE on error.
 */
function openssl_get_publickey(OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key): OpenSSLAsymmetricKey|false {}

/**
 * Generate a new signed public key and challenge
 * @param OpenSSLAsymmetricKey|resource $private_key privkey should be set to a private key that was previously generated by openssl_pkey_new() (or otherwise obtained from the other openssl_pkey family of functions). The corresponding public portion of the key will be used to sign the CSR.
 * @param string $challenge The challenge associated to associate with the SPKAC
 * @param int $digest_algo The digest algorithm. See openssl_get_md_method().
 * @return string|false Returns a signed public key and challenge string or FALSE on failure.
 * @since 5.6
 */
function openssl_spki_new(OpenSSLAsymmetricKey $private_key, string $challenge, int $digest_algo = 2): string|false {}

/**
 * Verifies a signed public key and challenge
 * @param string $spki Expects a valid signed public key and challenge
 * @return bool Returns a boolean on success or failure.
 * @since 5.6
 */
function openssl_spki_verify(string $spki): bool {}

/**
 * Exports the challenge associated with a signed public key and challenge
 * @param string $spki Expects a valid signed public key and challenge
 * @return string|false Returns the associated challenge string or FALSE on failure.
 * @since 5.6
 */
function openssl_spki_export_challenge(string $spki): string|false {}

/**
 * Exports a valid PEM formatted public key signed public key and challenge
 * @param string $spki Expects a valid signed public key and challenge
 * @return string|false Returns the associated PEM formatted public key or FALSE on failure.
 * @since 5.6
 */
function openssl_spki_export(string $spki): string|false {}

/**
 * Parse an X.509 certificate and return a resource identifier for
 * it
 * @param OpenSSLCertificate|string|resource $certificate X509 certificate. See Key/Certificate parameters for a list of valid values.
 * @return OpenSSLCertificate|resource|false a resource identifier on success or false on failure.
 */
function openssl_x509_read(OpenSSLCertificate|string $certificate): OpenSSLCertificate|false {}

/**
 * Calculates the fingerprint, or digest, of a given X.509 certificate
 *
 * openssl_x509_fingerprint returns the digest of certificate as a string.
 * @param string $certificate See Key/Certificate parameters for a list of valid values.
 * @param string $digest_algo [optional] hash method
 * @param bool $binary [optional]
 * @return string|false FALSE on failure
 * @since 5.6
 */
function openssl_x509_fingerprint(OpenSSLCertificate|string $certificate, string $digest_algo = 'sha1', bool $binary = false): string|false {}

/**
 * Free certificate resource
 * @param OpenSSLCertificate|resource|string $certificate
 * @return void No value is returned.
 * @deprecated
 */
function openssl_x509_free(OpenSSLCertificate $certificate): void {}

/**
 * Parse an X509 certificate and return the information as an array
 * @param OpenSSLCertificate|string|resource $certificate X509 certificate. See Key/Certificate parameters for a list of valid values.
 * @param bool $short_names [optional] shortnames controls how the data is indexed in the array - if shortnames is true (the default) then fields will be indexed with the short name form, otherwise, the long name form will be used - e.g.: CN is the shortname form of commonName.
 * @return array|false The structure of the returned data is (deliberately) not yet documented, as it is still subject to change.
 */
function openssl_x509_parse(
    OpenSSLCertificate|string $certificate,
    bool $short_names = true
): array|false {}

/**
 * Verifies if a certificate can be used for a particular purpose
 * @param OpenSSLCertificate|string|resource $certificate The examined certificate.
 * @param int $purpose openssl_x509_checkpurpose purposes Constant Description X509_PURPOSE_SSL_CLIENT Can the certificate be used for the client side of an SSL connection? X509_PURPOSE_SSL_SERVER Can the certificate be used for the server side of an SSL connection? X509_PURPOSE_NS_SSL_SERVER Can the ...
 * @param array $ca_info cainfo should be an array of trusted CA files/dirs as described in Certificate Verification.
 * @param string|null $untrusted_certificates_file [optional] If specified, this should be the name of a PEM encoded file holding certificates that can be used to help verify the certificate, although no trust is placed in the certificates that come from that file.
 * @return int|bool true if the certificate can be used for the intended purpose, false if it cannot, or -1 on error.
 */
function openssl_x509_checkpurpose(
    OpenSSLCertificate|string $certificate,
    int $purpose,
    array $ca_info = [],
    ?string $untrusted_certificates_file = null
): int|bool {}

/**
 * Checks if a private key corresponds to a certificate
 * @param OpenSSLCertificate|string|resource $certificate The certificate.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key The private key.
 * @return bool true if key is the private key that corresponds to cert, or false otherwise.
 */
function openssl_x509_check_private_key(
    OpenSSLCertificate|string $certificate,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key
): bool {}

/**
 * Exports a certificate as a string
 * @param OpenSSLCertificate|string|resource $certificate See Key/Certificate parameters for a list of valid values.
 * @param string &$output On success, this will hold the PEM.
 * @param bool $no_text [optional]
 * @return bool true on success or false on failure.
 */
function openssl_x509_export(OpenSSLCertificate|string $certificate, &$output, bool $no_text = true): bool {}

/**
 * Exports a certificate to file
 * @param OpenSSLCertificate|string|resource $certificate See Key/Certificate parameters for a list of valid values.
 * @param string $output_filename Path to the output file.
 * @param bool $no_text [optional]
 * @return bool true on success or false on failure.
 */
function openssl_x509_export_to_file(OpenSSLCertificate|string $certificate, string $output_filename, bool $no_text = true): bool {}

/**
 * Verifies digital signature of x509 certificate against a public key
 * @param OpenSSLCertificate|string|resource $certificate See Key/Certificate parameters for a list of valid values.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key OpenSSLAsymmetricKey - a key, returned by openssl_get_publickey string - a PEM formatted key (e.g. -----BEGIN PUBLIC KEY----- MIIBCgK...)
 * @return int Returns 1 if the signature is correct, 0 if it is incorrect, and -1 on error.
 * @since 7.4
 */
function openssl_x509_verify(
    OpenSSLCertificate|string $certificate,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key
): int {}

/**
 * Exports a PKCS#12 Compatible Certificate Store File to variable.
 * @param OpenSSLCertificate|string|resource $certificate See Key/Certificate parameters for a list of valid values.
 * @param string &$output On success, this will hold the PKCS#12.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key Private key component of PKCS#12 file.
 * @param string $passphrase Encryption password for unlocking the PKCS#12 file.
 * @param array $options Optional array, other keys will be ignored. Key Description "extracerts" array of extra certificates or a single certificate to be included in the PKCS#12 file. "friendly_name" string to be used for the supplied certificate and key
 * @return bool true on success or false on failure.
 * @since 5.2
 */
function openssl_pkcs12_export(
    OpenSSLCertificate|string $certificate,
    &$output,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    string $passphrase,
    array $options = []
): bool {}

/**
 * Exports a PKCS#12 Compatible Certificate Store File
 * @param OpenSSLCertificate|string|resource $certificate See Key/Certificate parameters for a list of valid values.
 * @param string $output_filename Path to the output file.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key Private key component of PKCS#12 file.
 * @param string $passphrase Encryption password for unlocking the PKCS#12 file.
 * @param array $options Optional array, other keys will be ignored. Key Description "extracerts" array of extra certificates or a single certificate to be included in the PKCS#12 file. "friendly_name" string to be used for the supplied certificate and key
 * @return bool true on success or false on failure.
 * @since 5.2
 */
function openssl_pkcs12_export_to_file(OpenSSLCertificate|string $certificate, string $output_filename, $private_key, string $passphrase, array $options = []): bool {}

/**
 * Parse a PKCS#12 Certificate Store into an array
 * @param string $pkcs12 The certificate store contents, not its file name.
 * @param array &$certificates On success, this will hold the Certificate Store Data.
 * @param string $passphrase Encryption password for unlocking the PKCS#12 file.
 * @return bool true on success or false on failure.
 * @since 5.2
 */
function openssl_pkcs12_read(string $pkcs12, &$certificates, string $passphrase): bool {}

/**
 * Generates a CSR
 * @param array $distinguished_names The Distinguished Name to be used in the certificate.
 * @param OpenSSLAsymmetricKey &$private_key privkey should be set to a private key that was previously generated by openssl_pkey_new (or otherwise obtained from the other openssl_pkey family of functions). The corresponding public portion of the key will be used to sign the CSR.
 * @param array|null $options [optional] By default, the information in your system openssl.conf is used to initialize the request; you can specify a configuration file section by setting the config_section_section key of configargs. You can also specify an alternative openssl configuration file by ...
 * @param array|null $extra_attributes [optional] extraattribs is used to specify additional configuration options for the CSR. Both dn and extraattribs are associative arrays whose keys are converted to OIDs and applied to the relevant part of the request.
 * @return OpenSSLCertificateSigningRequest|resource|false the CSR.
 */
function openssl_csr_new(
    array $distinguished_names,
    OpenSSLAsymmetricKey &$private_key,
    ?array $options = null,
    ?array $extra_attributes = null
): OpenSSLCertificateSigningRequest|bool {}

/**
 * Exports a CSR as a string
 * @param OpenSSLCertificateSigningRequest|string|resource $csr See CSR parameters for a list of valid values.
 * @param string &$output on success, this string will contain the PEM encoded CSR
 * @param bool $no_text [optional]
 * @return bool true on success or false on failure.
 */
function openssl_csr_export(OpenSSLCertificateSigningRequest|string $csr, &$output, bool $no_text = true): bool {}

/**
 * Exports a CSR to a file
 * @param OpenSSLCertificateSigningRequest|string|resource $csr See CSR parameters for a list of valid values.
 * @param string $output_filename Path to the output file.
 * @param bool $no_text [optional]
 * @return bool true on success or false on failure.
 */
function openssl_csr_export_to_file(OpenSSLCertificateSigningRequest|string $csr, string $output_filename, bool $no_text = true): bool {}

/**
 * Sign a CSR with another certificate (or itself) and generate a certificate
 * @param OpenSSLCertificateSigningRequest|string|resource $csr A CSR previously generated by openssl_csr_new. It can also be the path to a PEM encoded CSR when specified as file://path/to/csr or an exported string generated by openssl_csr_export.
 * @param OpenSSLCertificate|resource|string|null $ca_certificate The generated certificate will be signed by cacert. If cacert is null, the generated certificate will be a self-signed certificate.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key priv_key is the private key that corresponds to cacert.
 * @param int $days days specifies the length of time for which the generated certificate will be valid, in days.
 * @param array|null $options [optional] You can finetune the CSR signing by configargs. See openssl_csr_new for more information about configargs.
 * @param int $serial [optional] An optional the serial number of issued certificate. If not specified it will default to 0.
 * @param string|null $serial_hex An optional hexadecimal string representing the serial number of the issued certificate. If set, it takes precedence over the serial parameter value. If not specified or set to null, the serial parameter value is used instead.
 * @return OpenSSLCertificate|resource|false an x509 certificate resource on success, false on failure.
 */
function openssl_csr_sign(
    OpenSSLCertificateSigningRequest|string $csr,
    OpenSSLCertificate|string|null $ca_certificate,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    int $days,
    ?array $options = null,
    int $serial = 0
): OpenSSLCertificate|false {}

/**
 * Returns the subject of a CERT
 * @param OpenSSLCertificateSigningRequest|string|resource $csr See CSR parameters for a list of valid values.
 * @param bool $short_names [optional]
 * @return array|false Returns an associative array with subject description, or false on failure.
 */
function openssl_csr_get_subject(
    OpenSSLCertificateSigningRequest|string $csr,
    bool $short_names = true
): array|false {}

/**
 * Returns the public key of a CERT
 * @param OpenSSLCertificateSigningRequest|string|resource $csr See CSR parameters for a list of valid values.
 * @param bool $short_names [optional]
 * @return OpenSSLAsymmetricKey|resource|false Returns an OpenSSLAsymmetricKey on success, or false on error.
 */
function openssl_csr_get_public_key(
    OpenSSLCertificateSigningRequest|string $csr,
    bool $short_names = true
): OpenSSLAsymmetricKey|false {}

/**
 * Computes a digest
 * @param string $data The data.
 * @param string $digest_algo The digest method.
 * @param bool $binary [optional] Setting to true will return as raw output data, otherwise the return value is binhex encoded.
 * @return string|false the digested hash value on success or false on failure.
 */
function openssl_digest(string $data, string $digest_algo, bool $binary = false): string|false {}

/**
 * Encrypts data
 * @param string $data The data.
 * @param string $cipher_algo The cipher method. For a list of available cipher methods, use openssl_get_cipher_methods().
 * @param string $passphrase The key.
 * @param int $options [optional] options is a bitwise disjunction of the flags OPENSSL_RAW_DATA and OPENSSL_ZERO_PADDING.
 * @param string $iv [optional] A non-NULL Initialization Vector.
 * @param string &$tag [optional] The authentication tag passed by reference when using AEAD cipher mode (GCM or CCM).
 * @param string $aad [optional] Additional authentication data.
 * @param int $tag_length [optional] The length of the authentication tag. Its value can be between 4 and 16 for GCM mode.
 * @return string|false the encrypted string on success or false on failure.
 */
function openssl_encrypt(
    string $data,
    string $cipher_algo,
    string $passphrase,
    int $options = 0,
    string $iv = "",
    &$tag = null,
    string $aad = "",
    int $tag_length = 16
): string|false {}

/**
 * Decrypts data
 * @param string $data The data.
 * @param string $cipher_algo The cipher method.
 * @param string $passphrase The password.
 * @param int $options [optional] Setting to true will take a raw encoded string, otherwise a base64 string is assumed for the data parameter.
 * @param string $iv [optional] A non-NULL Initialization Vector.
 * @param string|null $tag The authentication tag in AEAD cipher mode. If it is incorrect, the authentication fails and the function returns FALSE.
 * @param string $aad [optional] Additional authentication data.
 * @return string|false The decrypted string on success or false on failure.
 */
function openssl_decrypt(
    string $data,
    string $cipher_algo,
    string $passphrase,
    int $options = 0,
    string $iv = "",
    string|null $tag = null,
    string $aad = ""
): string|false {}

/**
 * Gets the cipher iv length
 * @param string $cipher_algo The method.
 * @return int|false the cipher length on success, or false on failure.
 */
function openssl_cipher_iv_length(string $cipher_algo): int|false {}

/**
 * This function works in exactly the same way as openssl_cipher_iv_length but for a key length. This is especially
 * useful to make sure that the right key length is provided to openssl_encrypt and openssl_decrypt.
 * @param string $cipher_algo The cipher method, see openssl_get_cipher_methods for a list of potential values.
 * @return int|false Returns the cipher length on success, or false on failure.
 * @since 8.2
 */
function openssl_cipher_key_length(string $cipher_algo): int|false {}

/**
 * Generate signature
 * @param string $data The string of data you wish to sign
 * @param string &$signature If the call was successful the signature is returned in signature.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key OpenSSLAsymmetricKey - a key, returned by openssl_get_privatekey string - a PEM formatted key
 * @param string|int $algorithm [optional] For more information see the list of Signature Algorithms.
 * @param int $padding RSA PSS padding to use.
 * @param int $salt_length [optional] RSA PSS salt length, one of the OPENSSL_RSA_PSS_SALTLEN_* constants or a positive number of bytes. Since 8.6.
 * @return bool true on success or false on failure.
 */
function openssl_sign(
    string $data,
    &$signature,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    string|int $algorithm = OPENSSL_ALGO_SHA1,
    int $salt_length = OPENSSL_RSA_PSS_SALTLEN_AUTO
): bool {}

/**
 * Verify signature
 * @param string $data The string of data used to generate the signature previously
 * @param string $signature A raw binary string, generated by openssl_sign or similar means
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key OpenSSLAsymmetricKey - a key, returned by openssl_get_publickey string - a PEM formatted key (e.g. -----BEGIN PUBLIC KEY----- MIIBCgK...)
 * @param string|int $algorithm [optional] For more information see the list of Signature Algorithms.
 * @param int $padding RSA PSS padding to use.
 * @param int $salt_length [optional] RSA PSS salt length, one of the OPENSSL_RSA_PSS_SALTLEN_* constants or a positive number of bytes. Since 8.6.
 * @return int|false 1 if the signature is correct, 0 if it is incorrect, and -1 on error.
 */
function openssl_verify(
    string $data,
    string $signature,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key,
    string|int $algorithm = OPENSSL_ALGO_SHA1,
    int $salt_length = OPENSSL_RSA_PSS_SALTLEN_AUTO
): int|false {}

/**
 * Seal (encrypt) data
 * @param string $data The data to seal.
 * @param string &$sealed_data The sealed data.
 * @param array &$encrypted_keys Array of encrypted keys.
 * @param array $public_key Array of OpenSSLAsymmetricKey instances containing public keys.
 * @param string $cipher_algo The cipher method. The default value for PHP versions prior to 8.0 is ('RC4') which is considered insecure. It is strongly recommended to explicitly specify a secure cipher method.
 * @param string &$iv The initialization vector for decryption of data. It is required if the cipher method requires IV. This can be found out by calling openssl_cipher_iv_length with cipher_algo. The IV cannot be set explicitly. Any value set in it is overwritten by randomly generated value.
 * @return int|false the length of the sealed data on success, or false on error. If successful the sealed data is returned in sealed_data, and the envelope keys in env_keys.
 */
function openssl_seal(
    string $data,
    &$sealed_data,
    &$encrypted_keys,
    array $public_key,
    string $cipher_algo,
    &$iv = null
): int|false {}

/**
 * Open sealed data
 * @param string $data The sealed data.
 * @param string &$output If the call is successful the opened data is returned in this parameter.
 * @param string $encrypted_key The encrypted symmetric key that can be decrypted using private_key.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key The private key used for decrypting encrypted_key.
 * @param string $cipher_algo The cipher method.
 * @param string|null $iv [optional] The initialization vector.
 * @return bool true on success or false on failure.
 */
function openssl_open(
    string $data,
    &$output,
    string $encrypted_key,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    string $cipher_algo,
    ?string $iv = null
): bool {}

/**
 * Generates a PKCS5 v2 PBKDF2 string, defaults to SHA-1
 * @param string $password Password from which the derived key is generated.
 * @param string $salt PBKDF2 recommends a cryptographic salt of at least 128 bits (16 bytes).
 * @param int $key_length Length of desired output key.
 * @param int $iterations The number of iterations desired. NIST recommends at least 1,000. As of 2023, OWASP recommends 600,000 iterations for PBKDF2-HMAC-SHA256 and 210,000 for PBKDF2-HMAC-SHA512.
 * @param string $digest_algo [optional]
 * @return string|false Returns string or FALSE on failure.
 * @since 5.5
 */
function openssl_pbkdf2(string $password, string $salt, int $key_length, int $iterations, string $digest_algo = 'sha1'): string|false {}

/**
 * Verifies the signature of an S/MIME signed message
 * @param string $input_filename Path to the message.
 * @param int $flags flags can be used to affect how the signature is verified - see PKCS7 constants for more information.
 * @param string|null $signers_certificates_filename [optional] If the outfilename is specified, it should be a string holding the name of a file into which the certificates of the persons that signed the messages will be stored in PEM format.
 * @param array $ca_info If the cainfo is specified, it should hold information about the trusted CA certificates to use in the verification process - see certificate verification for more information about this parameter.
 * @param string|null $untrusted_certificates_filename [optional] If the extracerts is specified, it is the filename of a file containing a bunch of certificates to use as untrusted CAs.
 * @param string|null $content [optional] You can specify a filename with content that will be filled with the verified data, but with the signature information stripped.
 * @param string|null $output_filename [optional]
 * @return bool|int true if the signature is verified, false if it is not correct (the message has been tampered with, or the signing certificate is invalid), or -1 on error.
 */
function openssl_pkcs7_verify(
    string $input_filename,
    int $flags,
    ?string $signers_certificates_filename = null,
    array $ca_info = [],
    ?string $untrusted_certificates_filename = null,
    ?string $content = null,
    ?string $output_filename = null
): int|bool {}

/**
 * Decrypts an S/MIME encrypted message
 * @param string $input_filename
 * @param string $output_filename The decrypted message is written to the file specified by outfilename.
 * @param OpenSSLCertificate|string|resource $certificate
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string|null $private_key [optional]
 * @return bool true on success or false on failure.
 */
function openssl_pkcs7_decrypt(
    string $input_filename,
    string $output_filename,
    $certificate,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string|null $private_key = null
): bool {}

/**
 * Sign an S/MIME message
 * @param string $input_filename The input file you are intending to digitally sign.
 * @param string $output_filename The file which the digital signature will be written to.
 * @param OpenSSLCertificate|string|resource $certificate The X.509 certificate used to digitally sign input_filename. See Key/Certificate parameters for a list of valid values.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key private_key is the private key corresponding to certificate. See Public/Private Key parameters for a list of valid values.
 * @param array|null $headers headers is an array of headers that will be prepended to the data after it has been signed (see openssl_pkcs7_encrypt for more information about the format of this parameter).
 * @param int $flags [optional] flags can be used to alter the output - see PKCS7 constants.
 * @param string|null $untrusted_certificates_filename [optional] extracerts specifies the name of a file containing a bunch of extra certificates to include in the signature which can for example be used to help the recipient to verify the certificate that you used.
 * @return bool true on success or false on failure.
 */
function openssl_pkcs7_sign(
    string $input_filename,
    string $output_filename,
    OpenSSLCertificate|string $certificate,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    ?array $headers,
    int $flags = PKCS7_DETACHED,
    ?string $untrusted_certificates_filename = null
): bool {}

/**
 * Encrypt an S/MIME message
 * @param string $input_filename
 * @param string $output_filename
 * @param OpenSSLCertificate|array|string|resource $certificate Either a lone X.509 certificate, or an array of X.509 certificates.
 * @param array|null $headers headers is an array of headers that will be prepended to the data after it has been encrypted. headers can be either an associative array keyed by header name, or an indexed array, where each element contains a single header line.
 * @param int $flags [optional] flags can be used to specify options that affect the encoding process - see PKCS7 constants.
 * @param int $cipher_algo [optional] One of cipher constants.
 * @return bool true on success or false on failure.
 */
function openssl_pkcs7_encrypt(
    string $input_filename,
    string $output_filename,
    OpenSSLCertificate|array|string $certificate,
    ?array $headers,
    int $flags = 0,
    int $cipher_algo = OPENSSL_CIPHER_AES_128_CBC
): bool {}

/**
 * Encrypts data with private key
 * @param string $data
 * @param string &$encrypted_data
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key private_key must be the private key that corresponds to the public key that will be used to decrypt the data.
 * @param int $padding [optional] padding can be one of OPENSSL_PKCS1_PADDING, OPENSSL_NO_PADDING.
 * @return bool true on success or false on failure.
 */
function openssl_private_encrypt(
    string $data,
    &$encrypted_data,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    int $padding = OPENSSL_PKCS1_PADDING
): bool {}

/**
 * Decrypts data with private key
 * @param string $data
 * @param string &$decrypted_data
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key key must be the private key corresponding that was used to encrypt the data.
 * @param int $padding [optional] padding can be one of OPENSSL_PKCS1_PADDING, OPENSSL_SSLV23_PADDING, OPENSSL_PKCS1_OAEP_PADDING, OPENSSL_NO_PADDING.
 * @param string|null $digest_algo The digest algorithm for OAEP padding, or null to use the default algorithm.
 * @return bool true on success or false on failure.
 */
function openssl_private_decrypt(
    string $data,
    &$decrypted_data,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    int $padding = OPENSSL_PKCS1_PADDING
): bool {}

/**
 * Encrypts data with public key
 * @param string $data
 * @param string &$encrypted_data This will hold the result of the encryption.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key The public key.
 * @param int $padding [optional] padding can be one of OPENSSL_PKCS1_PADDING, OPENSSL_SSLV23_PADDING, OPENSSL_PKCS1_OAEP_PADDING, OPENSSL_NO_PADDING.
 * @param string|null $digest_algo The digest algorithm for OAEP padding, or null to use the default algorithm.
 * @return bool true on success or false on failure.
 */
function openssl_public_encrypt(
    string $data,
    &$encrypted_data,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key,
    int $padding = OPENSSL_PKCS1_PADDING
): bool {}

/**
 * Decrypts data with public key
 * @param string $data
 * @param string &$decrypted_data
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key key must be the public key corresponding that was used to encrypt the data.
 * @param int $padding [optional] padding can be one of OPENSSL_PKCS1_PADDING, OPENSSL_NO_PADDING.
 * @return bool true on success or false on failure.
 */
function openssl_public_decrypt(
    string $data,
    &$decrypted_data,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key,
    int $padding = OPENSSL_PKCS1_PADDING
): bool {}

/**
 * Gets available digest methods
 * @param bool $aliases [optional] Set to true if digest aliases should be included within the returned array.
 * @return array An array of available digest methods.
 */
function openssl_get_md_methods(bool $aliases = false): array {}

/**
 * Gets available cipher methods
 * @param bool $aliases [optional] Set to true if cipher aliases should be included within the returned array.
 * @return array An array of available cipher methods.
 */
function openssl_get_cipher_methods(bool $aliases = false): array {}

/**
 * Computes shared secret for public value of remote DH key and local DH key
 * @param string $public_key Public key
 * @param OpenSSLAsymmetricKey|resource $private_key DH key
 * @return string|false computed key on success or false on failure.
 * @since 5.3
 */
function openssl_dh_compute_key(string $public_key, OpenSSLAsymmetricKey $private_key): string|false {}

/**
 * Computes shared secret for public value of remote and local DH or ECDH key
 *
 * openssl_pkey_derive takes a set of a public_key and private_key and derives a shared secret, for
 * either DH or EC keys.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $public_key public_key is the public key for the derivation. See Public/Private Key parameters for a list of valid values.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key private_key is the private key for the derivation. See Public/Private Key parameters for a list of valid values.
 * @param int $key_length If not zero, will attempt to set the desired length of the derived secret. This parameter is deprecated and should not be used, as it does not work as expected. It never returns a secret longer than the size of the prime. If the desired length is smaller than the size of the ...
 * @return string|false The derived secret on success or false on failure.
 * @since 7.3
 */
function openssl_pkey_derive(
    $public_key,
    OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key,
    int $key_length = 0
): string|false {}

/**
 * Generates a string of pseudo-random bytes, with the number of bytes determined by the length parameter.
 * It also indicates if a cryptographically strong algorithm was used to produce the pseudo-random bytes,
 * and does this via the optional crypto_strong parameter. It's rare for this to be FALSE, but some systems may be broken or old.
 * @param positive-int $length The length of the desired string of bytes. Must be a positive integer. PHP will try to cast this parameter to a non-null integer to use it.
 * @param bool &$strong_result [optional] If passed into the function, this will hold a boolean value that determines if the algorithm used was "cryptographically strong", e.g., safe for usage with GPG, passwords, etc. true if it did, otherwise false
 * @return string|false the generated string of bytes on success, or false on failure.
 * @throws \Exception openssl_random_pseudo_bytes throws an Exception on failure.
 */
function openssl_random_pseudo_bytes(int $length, &$strong_result = null): string {}

/**
 * Return openSSL error message
 * @return string|false an error message string, or false if there are no more error messages to return.
 */
function openssl_error_string(): string|false {}

/**
 * Retrieve the available certificate locations
 * @return array an array with the available certificate locations
 * @since 5.6
 */
function openssl_get_cert_locations(): array {}

/**
 * Gets list of available curve names for ECC
 *
 * Gets the list of available curve names for use in Elliptic curve cryptography (ECC) for
 * public/private key operations. The two most widely standardized/supported curves are prime256v1
 * (NIST P-256) and secp384r1 (NIST P-384). Approximate Equivalancies of AES, RSA, DSA and ECC
 * Keysizes AES Symmetric Keysize (Bits) RSA and DSA Keysize (Bits) ECC Keysize (Bits) 80 1024 160
 * 112 2048 224 128 3072 256 192 7680 384 256 15360 512 NIST recommends using ECC curves with at
 * least 256 bits.
 * @return array|false An array of available curve names, or false on failure.
 */
function openssl_get_curve_names(): array|false {}

/**
 * Export the PKCS7 file to an array of PEM certificates
 * @param string $data The string of data you wish to parse (p7b format).
 * @param array &$certificates The array of PEM certificates from the p7b input data.
 * @return bool
 * @since 7.2
 */
function openssl_pkcs7_read(string $data, &$certificates): bool {}

/**
 * Verifies that the data block is intact, the signer is who they say they are, and returns the certs of the signers.
 * @param string $input_filename The input file.
 * @param int $flags [optional]
 * @param string|null $certificates [optional]
 * @param array $ca_info An array containing self-signed certificate authority certificates.
 * @param string|null $untrusted_certificates_filename [optional]
 * @param string|null $content [optional]
 * @param string|null $pk7 [optional]
 * @param string|null $sigfile [optional]
 * @param int $encoding [optional]
 * @return bool Returns true on success or false on failure.
 * @since 8.0
 */
function openssl_cms_verify(string $input_filename, int $flags = 0, ?string $certificates = null, array $ca_info = [], ?string $untrusted_certificates_filename = null, ?string $content = null, ?string $pk7 = null, ?string $sigfile = null, int $encoding = OPENSSL_ENCODING_SMIME): bool {}

/**
 * Encrypts the message in the file with the certificates and outputs the result to the supplied file.
 * @param string $input_filename The file to be encrypted.
 * @param string $output_filename The output file.
 * @param resource|string|array $certificate Recipients to encrypt to.
 * @param null|array $headers Headers to include when S/MIME is used.
 * @param int $flags Flags to be passed to CMS_sign.
 * @param int $encoding An encoding to output. One of OPENSSL_ENCODING_SMIME, OPENSSL_ENCODING_DER or OPENSSL_ENCODING_PEM.
 * @param int $cipher_algo A cipher to use.
 * @return bool Returns true on success or false on failure.
 * @since 8.0
 */
function openssl_cms_encrypt(string $input_filename, string $output_filename, $certificate, ?array $headers, int $flags = 0, int $encoding = OPENSSL_ENCODING_SMIME, int $cipher_algo = OPENSSL_CIPHER_AES_128_CBC): bool {}

/**
 * Signs the MIME message in the file with a cert and key and output the result to the supplied file.
 * @param string $input_filename The name of the file to be signed.
 * @param string $output_filename The name of the file to deposit the results.
 * @param OpenSSLCertificate|string $certificate The signing certificate. See Key/Certificate parameters for a list of valid values.
 * @param OpenSSLAsymmetricKey|OpenSSLCertificate|array|string $private_key The key associated with certificate. See Key/Certificate parameters for a list of valid values.
 * @param array|null $headers An array of headers to be included in S/MIME output.
 * @param int $flags [optional]
 * @param int $encoding [optional]
 * @param string|null $untrusted_certificates_filename [optional]
 * @return bool Returns true on success or false on failure.
 * @since 8.0
 */
function openssl_cms_sign(string $input_filename, string $output_filename, OpenSSLCertificate|string $certificate, $private_key, ?array $headers, int $flags = 0, int $encoding = OPENSSL_ENCODING_SMIME, ?string $untrusted_certificates_filename = null): bool {}

/**
 * Decrypts the S/MIME message in the file and outputs the results to the supplied file.
 * @param string $input_filename The name of a file containing encrypted content.
 * @param string $output_filename The name of the file to deposit the decrypted content.
 * @param resource|string $certificate The name of the file containing a certificate of the recipient.
 * @param resource|string|array $private_key The name of the file containing a PKCS#8 key.
 * @param int $encoding The encoding of the input file. One of OPENSSL_ENCODING_SMIME, OPENSSL_ENCODING_DER or OPENSSL_ENCODING_PEM.
 * @return bool Returns true on success or false on failure.
 * @since 8.0
 */
function openssl_cms_decrypt(string $input_filename, string $output_filename, $certificate, $private_key = null, int $encoding = OPENSSL_ENCODING_SMIME): bool {}

/**
 * Exports the CMS file to an array of PEM certificates.
 * @param string $input_filename
 * @param array &$certificates
 * @return bool
 * @since 8.0
 */
function openssl_cms_read(string $input_filename, &$certificates): bool {}
