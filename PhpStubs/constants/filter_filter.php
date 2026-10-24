<?php

/**
 * POST variables.
 */
const INPUT_POST = 0;

/**
 * GET variables.
 */
const INPUT_GET = 1;

/**
 * COOKIE variables.
 */
const INPUT_COOKIE = 2;

/**
 * ENV variables.
 */
const INPUT_ENV = 4;

/**
 * SERVER variables.
 */
const INPUT_SERVER = 5;

/**
 * SESSION variables.
 * (not implemented yet)
 * @removed 8.0
 */
const INPUT_SESSION = 6;

/**
 * REQUEST variables.
 * (not implemented yet)
 * @removed 8.0
 */
const INPUT_REQUEST = 99;

/**
 * No flags.
 */
const FILTER_FLAG_NONE = 0;

/**
 * Flag used to require scalar as input
 */
const FILTER_REQUIRE_SCALAR = 33554432;

/**
 * Require an array as input.
 */
const FILTER_REQUIRE_ARRAY = 16777216;

/**
 * Always returns an array.
 */
const FILTER_FORCE_ARRAY = 67108864;

/**
 * Use NULL instead of FALSE on failure.
 */
const FILTER_NULL_ON_FAILURE = 134217728;

/**
 * ID of "int" filter.
 */
const FILTER_VALIDATE_INT = 257;

/**
 * ID of "boolean" filter.
 */
const FILTER_VALIDATE_BOOLEAN = 258;

/**
 * ID of "boolean" filter.
 * @since 8.0 Using `FILTER_VALIDATE_BOOL` is preferred.
 */
const FILTER_VALIDATE_BOOL = 258;

/**
 * ID of "float" filter.
 */
const FILTER_VALIDATE_FLOAT = 259;

/**
 * ID of "validate_regexp" filter.
 */
const FILTER_VALIDATE_REGEXP = 272;

const FILTER_VALIDATE_DOMAIN = 277;

/**
 * ID of "validate_url" filter.
 */
const FILTER_VALIDATE_URL = 273;

/**
 * ID of "validate_email" filter.
 */
const FILTER_VALIDATE_EMAIL = 274;

/**
 * ID of "validate_ip" filter.
 */
const FILTER_VALIDATE_IP = 275;

const FILTER_VALIDATE_MAC = 276;

/**
 * ID of default ("string") filter.
 * @deprecated 8.5 use FILTER_UNSAFE_RAW instead
 */
const FILTER_DEFAULT = 516;

/**
 * @since 7.3
 */
const FILTER_SANITIZE_ADD_SLASHES = 523;

/**
 * ID of "unsafe_raw" filter.
 */
const FILTER_UNSAFE_RAW = 516;

/**
 * ID of "string" filter.
 * @deprecated 8.1
 */
const FILTER_SANITIZE_STRING = 513;

/**
 * ID of "stripped" filter.
 * @deprecated 8.1
 */
const FILTER_SANITIZE_STRIPPED = 513;

/**
 * ID of "encoded" filter.
 */
const FILTER_SANITIZE_ENCODED = 514;

/**
 * ID of "special_chars" filter.
 */
const FILTER_SANITIZE_SPECIAL_CHARS = 515;

const FILTER_SANITIZE_FULL_SPECIAL_CHARS = 522;

/**
 * ID of "email" filter.
 */
const FILTER_SANITIZE_EMAIL = 517;

/**
 * ID of "url" filter.
 */
const FILTER_SANITIZE_URL = 518;

/**
 * ID of "number_int" filter.
 */
const FILTER_SANITIZE_NUMBER_INT = 519;

/**
 * ID of "number_float" filter.
 */
const FILTER_SANITIZE_NUMBER_FLOAT = 520;

/**
 * ID of "magic_quotes" filter.
 * @deprecated 7.4
 * @removed 8.0
 */
const FILTER_SANITIZE_MAGIC_QUOTES = 521;

/**
 * ID of "callback" filter.
 */
const FILTER_CALLBACK = 1024;

/**
 * Allow octal notation (0[0-7]+) in "int" filter.
 */
const FILTER_FLAG_ALLOW_OCTAL = 1;

/**
 * Allow hex notation (0x[0-9a-fA-F]+) in "int" filter.
 */
const FILTER_FLAG_ALLOW_HEX = 2;

/**
 * Strip characters with ASCII value less than 32.
 */
const FILTER_FLAG_STRIP_LOW = 4;

/**
 * Strip characters with ASCII value greater than 127.
 */
const FILTER_FLAG_STRIP_HIGH = 8;

const FILTER_FLAG_STRIP_BACKTICK = 512;

/**
 * Encode characters with ASCII value less than 32.
 */
const FILTER_FLAG_ENCODE_LOW = 16;

/**
 * Encode characters with ASCII value greater than 127.
 */
const FILTER_FLAG_ENCODE_HIGH = 32;

/**
 * Encode &.
 */
const FILTER_FLAG_ENCODE_AMP = 64;

/**
 * Don't encode ' and ".
 */
const FILTER_FLAG_NO_ENCODE_QUOTES = 128;

/**
 * (No use for now.)
 */
const FILTER_FLAG_EMPTY_STRING_NULL = 256;

/**
 * Allow fractional part in "number_float" filter.
 */
const FILTER_FLAG_ALLOW_FRACTION = 4096;

/**
 * Allow thousand separator (,) in "number_float" filter.
 */
const FILTER_FLAG_ALLOW_THOUSAND = 8192;

/**
 * Allow scientific notation (e, E) in
 * "number_float" filter.
 */
const FILTER_FLAG_ALLOW_SCIENTIFIC = 16384;

/**
 * Require scheme in "validate_url" filter.
 * @deprecated 7.3
 * @removed 8.0
 */
const FILTER_FLAG_SCHEME_REQUIRED = 65536;

/**
 * Require host in "validate_url" filter.
 * @deprecated 7.3
 * @removed 8.0
 */
const FILTER_FLAG_HOST_REQUIRED = 131072;

/**
 * Require path in "validate_url" filter.
 */
const FILTER_FLAG_PATH_REQUIRED = 262144;

/**
 * Require query in "validate_url" filter.
 */
const FILTER_FLAG_QUERY_REQUIRED = 524288;

/**
 * Allow only IPv4 address in "validate_ip" filter.
 */
const FILTER_FLAG_IPV4 = 1048576;

/**
 * Allow only IPv6 address in "validate_ip" filter.
 */
const FILTER_FLAG_IPV6 = 2097152;

/**
 * Deny reserved addresses in "validate_ip" filter.
 */
const FILTER_FLAG_NO_RES_RANGE = 4194304;

/**
 * Deny private addresses in "validate_ip" filter.
 */
const FILTER_FLAG_NO_PRIV_RANGE = 8388608;

const FILTER_FLAG_HOSTNAME = 1048576;

const FILTER_FLAG_EMAIL_UNICODE = 1048576;

/**
 * filters Global IPs per RFC 6890
 * @since 8.2
 */
const FILTER_FLAG_GLOBAL_RANGE = 536870912;

const FILTER_THROW_ON_FAILURE = 268435456;
