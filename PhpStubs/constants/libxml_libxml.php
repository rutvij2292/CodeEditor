<?php

/**
 * libxml version like 20605 or 20617
 */
const LIBXML_VERSION = 20901;

/**
 * libxml version like 2.6.5 or 2.6.17
 */
const LIBXML_DOTTED_VERSION = "2.9.1";

const LIBXML_LOADED_VERSION = 20901;

/**
 * Substitute entities
 */
const LIBXML_NOENT = 2;

/**
 * Load the external subset
 */
const LIBXML_DTDLOAD = 4;

/**
 * Default DTD attributes
 */
const LIBXML_DTDATTR = 8;

/**
 * Validate with the DTD
 */
const LIBXML_DTDVALID = 16;

/**
 * Suppress error reports
 */
const LIBXML_NOERROR = 32;

/**
 * Suppress warning reports
 */
const LIBXML_NOWARNING = 64;

/**
 * Remove blank nodes
 */
const LIBXML_NOBLANKS = 256;

/**
 * Implement XInclude substitution
 */
const LIBXML_XINCLUDE = 1024;

/**
 * Remove redundant namespaces declarations
 */
const LIBXML_NSCLEAN = 8192;

/**
 * Merge CDATA as text nodes
 */
const LIBXML_NOCDATA = 16384;

/**
 * Disable network access when loading documents
 */
const LIBXML_NONET = 2048;

/**
 * Sets XML_PARSE_PEDANTIC flag, which enables pedentic error reporting.
 * @since 5.4
 */
const LIBXML_PEDANTIC = 128;

/**
 * Activate small nodes allocation optimization. This may speed up your
 * application without needing to change the code.
 *
 * Only available in Libxml >= 2.6.21
 */
const LIBXML_COMPACT = 65536;

/**
 * Allows line numbers greater than 65535 to be reported correctly.
 *
 * Only available in Libxml >= 2.9.0
 */
const LIBXML_BIGLINES = 65535;

/**
 * Drop the XML declaration when saving a document
 *
 * Only available in Libxml >= 2.6.21
 */
const LIBXML_NOXMLDECL = 2;

/**
 * Sets XML_PARSE_HUGE flag, which relaxes any hardcoded limit from the parser. This affects
 * limits like maximum depth of a document or the entity recursion, as well as limits of the
 * size of text nodes.
 *
 * Only available in Libxml >= 2.7.0 (as of PHP >= 5.3.2 and PHP >= 5.2.12)
 */
const LIBXML_PARSEHUGE = 524288;

/**
 * Expand empty tags (e.g. <br/> to
 * <br></br>)
 *
 * This option is currently just available in the
 * and
 * functions.
 */
const LIBXML_NOEMPTYTAG = 4;

/**
 * Create default/fixed value nodes during XSD schema validation
 *
 * Only available in Libxml >= 2.6.14 (as of PHP >= 5.5.2)
 */
const LIBXML_SCHEMA_CREATE = 1;

/**
 * Sets HTML_PARSE_NOIMPLIED flag, which turns off the
 * automatic adding of implied html/body... elements.
 *
 * Only available in Libxml >= 2.7.7 (as of PHP >= 5.4.0)
 */
const LIBXML_HTML_NOIMPLIED = 8192;

/**
 * Sets HTML_PARSE_NODEFDTD flag, which prevents a default doctype
 * being added when one is not found.
 *
 * Only available in Libxml >= 2.7.8 (as of PHP >= 5.4.0)
 */
const LIBXML_HTML_NODEFDTD = 4;

/**
 * No errors
 */
const LIBXML_ERR_NONE = 0;

/**
 * A simple warning
 */
const LIBXML_ERR_WARNING = 1;

/**
 * A recoverable error
 */
const LIBXML_ERR_ERROR = 2;

/**
 * A fatal error
 */
const LIBXML_ERR_FATAL = 3;

/**
 * @since 8.4
 */
const LIBXML_RECOVER = 1;

const LIBXML_NO_XXE = 8388608;
