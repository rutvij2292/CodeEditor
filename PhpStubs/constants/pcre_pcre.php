<?php

/**
 * Orders results so that $matches[0] is an array of full pattern
 * matches, $matches[1] is an array of strings matched by the first
 * parenthesized subpattern, and so on. This flag is only used with
 * preg_match_all.
 */
const PREG_PATTERN_ORDER = 1;

/**
 * Returned by preg_last_error() if the last PCRE function failed due to limited JIT stack space.
 * @since 7.0
 */
const PREG_JIT_STACKLIMIT_ERROR = 6;

/**
 * Orders results so that $matches[0] is an array of first set of
 * matches, $matches[1] is an array of second set of matches, and so
 * on. This flag is only used with preg_match_all.
 */
const PREG_SET_ORDER = 2;

/**
 * See the description of
 * PREG_SPLIT_OFFSET_CAPTURE.
 */
const PREG_OFFSET_CAPTURE = 256;

/**
 * This flag tells preg_split to return only non-empty
 * pieces.
 */
const PREG_SPLIT_NO_EMPTY = 1;

/**
 * This flag tells preg_split to capture
 * parenthesized expression in the delimiter pattern as well.
 */
const PREG_SPLIT_DELIM_CAPTURE = 2;

/**
 * If this flag is set, for every occurring match the appendant string
 * offset will also be returned. Note that this changes the return
 * values in an array where every element is an array consisting of the
 * matched string at offset 0 and its string offset within subject at
 * offset 1. This flag is only used for preg_split.
 */
const PREG_SPLIT_OFFSET_CAPTURE = 4;

const PREG_GREP_INVERT = 1;

/**
 * Returned by preg_last_error if there were no
 * errors.
 */
const PREG_NO_ERROR = 0;

/**
 * Returned by preg_last_error if there was an
 * internal PCRE error.
 */
const PREG_INTERNAL_ERROR = 1;

/**
 * Returned by preg_last_error if backtrack limit was exhausted.
 */
const PREG_BACKTRACK_LIMIT_ERROR = 2;

/**
 * Returned by preg_last_error if recursion limit was exhausted.
 */
const PREG_RECURSION_LIMIT_ERROR = 3;

/**
 * Returned by preg_last_error if the last error was
 * caused by malformed UTF-8 data (only when running a regex in UTF-8 mode).
 */
const PREG_BAD_UTF8_ERROR = 4;

/**
 * Returned by preg_last_error if the offset didn't
 * correspond to the begin of a valid UTF-8 code point (only when running
 * a regex in UTF-8
 * mode).
 */
const PREG_BAD_UTF8_OFFSET_ERROR = 5;

/**
 * This flag tells preg_match() and preg_match_all()
 * to include unmatched subpatterns in $matches as NULL values.
 * Without this flag, unmatched subpatterns are reported as empty strings,
 * as if they were empty matches. Setting this flag allows to distinguish between these two cases.
 * @since 7.2
 */
const PREG_UNMATCHED_AS_NULL = 512;

/**
 * PCRE version and release date (e.g. "7.0 18-Dec-2006").
 */
const PCRE_VERSION = "8.31 2012-07-06";

/**
 * @since 7.3
 */
const PCRE_VERSION_MAJOR = 10;

/**
 * @since 7.3
 */
const PCRE_VERSION_MINOR = 42;

/**
 * @since 7.3
 */
const PCRE_JIT_SUPPORT = 1;
