<?php

const DATE_ATOM = "Y-m-d\TH:i:sP";

const DATE_COOKIE = "l, d-M-Y H:i:s T";

/**
 * This format is not compatible with ISO-8601, but is left this way for backward compatibility reasons.
 * Use DateTime::ATOM or DATE_ATOM for compatibility with ISO-8601 instead.
 * @deprecated
 */
const DATE_ISO8601 = "Y-m-d\TH:i:sO";

/**
 * @since 8.2
 */
const DATE_ISO8601_EXPANDED = "X-m-d\\TH:i:sP";

const DATE_RFC822 = "D, d M y H:i:s O";

const DATE_RFC850 = "l, d-M-y H:i:s T";

const DATE_RFC1036 = "D, d M y H:i:s O";

const DATE_RFC1123 = "D, d M Y H:i:s O";

const DATE_RFC2822 = "D, d M Y H:i:s O";

const DATE_RFC3339 = "Y-m-d\TH:i:sP";

const DATE_RFC3339_EXTENDED = "Y-m-d\TH:i:s.vP";

/**
 * @deprecated 8.5
 */
const DATE_RFC7231 = "D, d M Y H:i:s \G\M\T";

const DATE_RSS = "D, d M Y H:i:s O";

const DATE_W3C = "Y-m-d\TH:i:sP";

/**
 * Timestamp
 * @deprecated 8.4
 */
const SUNFUNCS_RET_TIMESTAMP = 0;

/**
 * Hours:minutes (example: 08:02)
 * @deprecated 8.4
 */
const SUNFUNCS_RET_STRING = 1;

/**
 * Hours as floating point number (example 8.75)
 * @deprecated 8.4
 */
const SUNFUNCS_RET_DOUBLE = 2;
