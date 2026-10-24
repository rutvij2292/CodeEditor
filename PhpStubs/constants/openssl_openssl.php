<?php

const OPENSSL_VERSION_TEXT = "OpenSSL 1.0.0e 6 Sep 2011";

const OPENSSL_VERSION_NUMBER = 268435551;

const X509_PURPOSE_SSL_CLIENT = 1;

const X509_PURPOSE_SSL_SERVER = 2;

const X509_PURPOSE_NS_SSL_SERVER = 3;

const X509_PURPOSE_SMIME_SIGN = 4;

const X509_PURPOSE_SMIME_ENCRYPT = 5;

const X509_PURPOSE_CRL_SIGN = 6;

const X509_PURPOSE_ANY = 7;

/**
 * @since 8.4
 */
const X509_PURPOSE_OCSP_HELPER = 8;

/**
 * @since 8.4
 */
const X509_PURPOSE_TIMESTAMP_SIGN = 9;

/**
 * Used as default algorithm by openssl_sign and
 * openssl_verify.
 */
const OPENSSL_ALGO_SHA1 = 1;

const OPENSSL_ALGO_MD5 = 2;

const OPENSSL_ALGO_MD4 = 3;

const OPENSSL_ALGO_MD2 = 4;

const OPENSSL_ALGO_DSS1 = 5;

const OPENSSL_ALGO_SHA224 = 6;

const OPENSSL_ALGO_SHA256 = 7;

const OPENSSL_ALGO_SHA384 = 8;

const OPENSSL_ALGO_SHA512 = 9;

const OPENSSL_ALGO_RMD160 = 10;

/**
 * When signing a message, use cleartext signing with the MIME
 * type "multipart/signed". This is the default
 * if you do not specify any flags to
 * openssl_pkcs7_sign.
 * If you turn this option off, the message will be signed using
 * opaque signing, which is more resistant to translation by mail relays
 * but cannot be read by mail agents that do not support S/MIME.
 */
const PKCS7_DETACHED = 64;

/**
 * Adds text/plain content type headers to encrypted/signed
 * message. If decrypting or verifying, it strips those headers from
 * the output - if the decrypted or verified message is not of MIME type
 * text/plain then an error will occur.
 */
const PKCS7_TEXT = 1;

/**
 * When verifying a message, certificates (if
 * any) included in the message are normally searched for the
 * signing certificate. With this option only the
 * certificates specified in the extracerts
 * parameter of openssl_pkcs7_verify are
 * used. The supplied certificates can still be used as
 * untrusted CAs however.
 */
const PKCS7_NOINTERN = 16;

/**
 * Do not verify the signers certificate of a signed
 * message.
 */
const PKCS7_NOVERIFY = 32;

/**
 * Do not chain verification of signers certificates: that is
 * don't use the certificates in the signed message as untrusted CAs.
 */
const PKCS7_NOCHAIN = 8;

/**
 * When signing a message the signer's certificate is normally
 * included - with this option it is excluded. This will reduce the
 * size of the signed message but the verifier must have a copy of the
 * signers certificate available locally (passed using the
 * extracerts to
 * openssl_pkcs7_verify for example).
 */
const PKCS7_NOCERTS = 2;

/**
 * Normally when a message is signed, a set of attributes are
 * included which include the signing time and the supported symmetric
 * algorithms. With this option they are not included.
 */
const PKCS7_NOATTR = 256;

/**
 * Normally the input message is converted to "canonical" format
 * which is effectively using CR and LF
 * as end of line: as required by the S/MIME specification. When this
 * option is present, no translation occurs. This is useful when
 * handling binary data which may not be in MIME format.
 */
const PKCS7_BINARY = 128;

/**
 * @since 8.3
 */
const PKCS7_NOOLDMIMETYPE = 1024;

/**
 * Don't try and verify the signatures on a message
 */
const PKCS7_NOSIGS = 4;

const OPENSSL_PKCS1_PADDING = 1;

const OPENSSL_SSLV23_PADDING = 2;

const OPENSSL_NO_PADDING = 3;

const OPENSSL_PKCS1_OAEP_PADDING = 4;

/**
 * @since 8.6
 */
const OPENSSL_RSA_PSS_SALTLEN_DIGEST = -1;

/**
 * @since 8.6
 */
const OPENSSL_RSA_PSS_SALTLEN_AUTO = -2;

/**
 * @since 8.6
 */
const OPENSSL_RSA_PSS_SALTLEN_MAX = -3;

const OPENSSL_CIPHER_RC2_40 = 0;

const OPENSSL_CIPHER_RC2_128 = 1;

const OPENSSL_CIPHER_RC2_64 = 2;

const OPENSSL_CIPHER_DES = 3;

const OPENSSL_CIPHER_3DES = 4;

const OPENSSL_KEYTYPE_RSA = 0;

const OPENSSL_KEYTYPE_DSA = 1;

const OPENSSL_KEYTYPE_DH = 2;

const OPENSSL_KEYTYPE_EC = 3;

/**
 * @since 8.4
 */
const OPENSSL_KEYTYPE_X25519 = 4;

/**
 * @since 8.4
 */
const OPENSSL_KEYTYPE_ED25519 = 5;

/**
 * @since 8.4
 */
const OPENSSL_KEYTYPE_X448 = 6;

/**
 * @since 8.4
 */
const OPENSSL_KEYTYPE_ED448 = 7;

/**
 * Whether SNI support is available or not.
 */
const OPENSSL_TLSEXT_SERVER_NAME = 1;

const OPENSSL_CIPHER_AES_128_CBC = 5;

const OPENSSL_CIPHER_AES_192_CBC = 6;

const OPENSSL_CIPHER_AES_256_CBC = 7;

const OPENSSL_RAW_DATA = 1;

const OPENSSL_ZERO_PADDING = 2;

const OPENSSL_DONT_ZERO_PAD_KEY = 4;

/**
 * @since 8.0
 */
const OPENSSL_CMS_DETACHED = 64;

/**
 * @since 8.0
 */
const OPENSSL_CMS_TEXT = 1;

/**
 * @since 8.0
 */
const OPENSSL_CMS_NOINTERN = 16;

/**
 * @since 8.0
 */
const OPENSSL_CMS_NOVERIFY = 32;

/**
 * @since 8.0
 */
const OPENSSL_CMS_NOCERTS = 2;

/**
 * @since 8.0
 */
const OPENSSL_CMS_NOATTR = 256;

/**
 * @since 8.0
 */
const OPENSSL_CMS_BINARY = 128;

/**
 * @since 8.0
 */
const OPENSSL_CMS_NOSIGS = 12;

/**
 * @since 8.0
 */
const OPENSSL_ENCODING_DER = 0;

/**
 * @since 8.0
 */
const OPENSSL_ENCODING_SMIME = 1;

/**
 * @since 8.0
 */
const OPENSSL_ENCODING_PEM = 2;

const OPENSSL_DEFAULT_STREAM_CIPHERS = "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:" . "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:" . "DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:" . "ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:" . "ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:" . "DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:" . "AES256-GCM-SHA384:AES128:AES256:HIGH:!SSLv2:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!RC4:!ADH";

/**
 * @since 8.3
 */
const OPENSSL_CMS_OLDMIMETYPE = 1024;

const PKCS7_NOSMIMECAP = '512';

const PKCS7_CRLFEOL = 2048;

const PKCS7_NOCRL = 8192;

const PKCS7_NO_DUAL_CONTENT = 65536;

const OPENSSL_PKCS1_PSS_PADDING = 6;

const CURLOPT_INFILESIZE_LARGE = 30115;
