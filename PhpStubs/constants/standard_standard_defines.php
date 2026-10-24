<?php

const CONNECTION_ABORTED = 1;

const CONNECTION_NORMAL = 0;

const CONNECTION_TIMEOUT = 2;

const INI_USER = 1;

const INI_PERDIR = 2;

const INI_SYSTEM = 4;

const INI_ALL = 7;

/**
 * Normal INI scanner mode
 */
const INI_SCANNER_NORMAL = 0;

/**
 * Typed INI scanner mode
 * @since 5.6
 */
const INI_SCANNER_TYPED = 2;

/**
 * Raw INI scanner mode
 */
const INI_SCANNER_RAW = 1;

const PHP_URL_SCHEME = 0;

const PHP_URL_HOST = 1;

const PHP_URL_PORT = 2;

const PHP_URL_USER = 3;

const PHP_URL_PASS = 4;

const PHP_URL_PATH = 5;

const PHP_URL_QUERY = 6;

const PHP_URL_FRAGMENT = 7;

/**
 * e constant
 */
const M_E = 2.718281828459;

/**
 * log<sub>2</sub>e constant
 */
const M_LOG2E = 1.442695040889;

/**
 * log<sub>10</sub>e constant
 */
const M_LOG10E = 0.43429448190325;

/**
 * log<sub>e</sub>2 constant
 */
const M_LN2 = 0.69314718055995;

/**
 * log<sub>e</sub>10 constant
 */
const M_LN10 = 2.302585092994;

/**
 * π constant
 */
const M_PI = 3.1415926535898;

/**
 * π/2 constant
 */
const M_PI_2 = 1.5707963267949;

/**
 * π/4 constant
 */
const M_PI_4 = 0.78539816339745;

/**
 * 1/π constant
 */
const M_1_PI = 0.31830988618379;

/**
 * 2/π constant
 */
const M_2_PI = 0.63661977236758;

/**
 * sqrt(π) constant
 */
const M_SQRTPI = 1.7724538509055;

/**
 * 2/sqrt(π) constant
 */
const M_2_SQRTPI = 1.1283791670955;

/**
 * log<sub>e</sub>π constant
 */
const M_LNPI = 1.1447298858494;

/**
 * Euler constant
 */
const M_EULER = 0.57721566490153;

/**
 * sqrt(2) constant
 */
const M_SQRT2 = 1.4142135623731;

/**
 * 1/sqrt(2) constant
 */
const M_SQRT1_2 = 0.70710678118655;

/**
 * sqrt(3) constant
 */
const M_SQRT3 = 1.7320508075689;

/**
 * The infinite
 */
const INF = (float)INF;

/**
 * Not A Number
 */
const NAN = (float)NAN;

/**
 * Round halves up
 */
const PHP_ROUND_HALF_UP = 1;

/**
 * Round halves down
 */
const PHP_ROUND_HALF_DOWN = 2;

/**
 * Round halves to even numbers
 */
const PHP_ROUND_HALF_EVEN = 3;

/**
 * Round halves to odd numbers
 */
const PHP_ROUND_HALF_ODD = 4;

const INFO_GENERAL = 1;

/**
 * PHP Credits. See also phpcredits.
 */
const INFO_CREDITS = 2;

/**
 * Current Local and Main values for PHP directives. See
 * also ini_get.
 */
const INFO_CONFIGURATION = 4;

/**
 * Loaded modules and their respective settings.
 */
const INFO_MODULES = 8;

/**
 * Environment Variable information that's also available in
 * $_ENV.
 */
const INFO_ENVIRONMENT = 16;

/**
 * Shows all
 * predefined variables from EGPCS (Environment, GET,
 * POST, Cookie, Server).
 */
const INFO_VARIABLES = 32;

/**
 * PHP License information. See also the license faq.
 */
const INFO_LICENSE = 64;

const INFO_ALL = 4294967295;

/**
 * A list of the core developers
 */
const CREDITS_GROUP = 1;

/**
 * General credits: Language design and concept, PHP
 * authors and SAPI module.
 */
const CREDITS_GENERAL = 2;

/**
 * A list of the server API modules for PHP, and their authors.
 */
const CREDITS_SAPI = 4;

/**
 * A list of the extension modules for PHP, and their authors.
 */
const CREDITS_MODULES = 8;

/**
 * The credits for the documentation team.
 */
const CREDITS_DOCS = 16;

/**
 * Usually used in combination with the other flags. Indicates
 * that a complete stand-alone HTML page needs to be
 * printed including the information indicated by the other
 * flags.
 */
const CREDITS_FULLPAGE = 32;

/**
 * The credits for the quality assurance team.
 */
const CREDITS_QA = 64;

/**
 * The configuration line, "php.ini" location, build date, Web
 * Server, System and more.
 */
const CREDITS_ALL = 4294967295;

const HTML_SPECIALCHARS = 0;

const HTML_ENTITIES = 1;

/**
 * Will convert double-quotes and leave single-quotes alone.
 */
const ENT_COMPAT = 2;

/**
 * Will convert both double and single quotes.
 */
const ENT_QUOTES = 3;

/**
 * Will leave both double and single quotes unconverted.
 */
const ENT_NOQUOTES = 0;

/**
 * Silently discard invalid code unit sequences instead of returning an empty string.
 * Using this flag is discouraged as it may have security implications.
 */
const ENT_IGNORE = 4;

const STR_PAD_LEFT = 0;

const STR_PAD_RIGHT = 1;

const STR_PAD_BOTH = 2;

const PATHINFO_DIRNAME = 1;

const PATHINFO_BASENAME = 2;

const PATHINFO_EXTENSION = 4;

const PATHINFO_FILENAME = 8;

const PATHINFO_ALL = 15;

const CHAR_MAX = 127;

const LC_CTYPE = 0;

const LC_NUMERIC = 1;

const LC_TIME = 2;

const LC_COLLATE = 3;

const LC_MONETARY = 4;

const LC_ALL = 6;

const LC_MESSAGES = 5;

const SEEK_SET = 0;

const SEEK_CUR = 1;

const SEEK_END = 2;

/**
 * Acquire a shared lock (reader).
 */
const LOCK_SH = 1;

/**
 * Acquire an exclusive lock (writer).
 */
const LOCK_EX = 2;

/**
 * Release lock (shared or exclusive).
 */
const LOCK_UN = 3;

/**
 * Non-blocking operation while locking.
 */
const LOCK_NB = 4;

/**
 * A connection with an external resource has been established.
 */
const STREAM_NOTIFY_CONNECT = 2;

/**
 * Additional authorization is required to access the specified resource.
 * Typical issued with severity level of
 * STREAM_NOTIFY_SEVERITY_ERR.
 */
const STREAM_NOTIFY_AUTH_REQUIRED = 3;

/**
 * Authorization has been completed (with or without success).
 */
const STREAM_NOTIFY_AUTH_RESULT = 10;

/**
 * The mime-type of resource has been identified,
 * refer to message for a description of the
 * discovered type.
 */
const STREAM_NOTIFY_MIME_TYPE_IS = 4;

/**
 * The size of the resource has been discovered.
 */
const STREAM_NOTIFY_FILE_SIZE_IS = 5;

/**
 * The external resource has redirected the stream to an alternate
 * location. Refer to message.
 */
const STREAM_NOTIFY_REDIRECTED = 6;

/**
 * Indicates current progress of the stream transfer in
 * bytes_transferred and possibly
 * bytes_max as well.
 */
const STREAM_NOTIFY_PROGRESS = 7;

/**
 * A generic error occurred on the stream, consult
 * message and message_code
 * for details.
 */
const STREAM_NOTIFY_FAILURE = 9;

/**
 * There is no more data available on the stream.
 */
const STREAM_NOTIFY_COMPLETED = 8;

/**
 * A remote address required for this stream has been resolved, or the resolution
 * failed. See severity for an indication of which happened.
 */
const STREAM_NOTIFY_RESOLVE = 1;

/**
 * Normal, non-error related, notification.
 */
const STREAM_NOTIFY_SEVERITY_INFO = 0;

/**
 * Non critical error condition. Processing may continue.
 */
const STREAM_NOTIFY_SEVERITY_WARN = 1;

/**
 * A critical error occurred. Processing cannot continue.
 */
const STREAM_NOTIFY_SEVERITY_ERR = 2;

/**
 * Used with stream_filter_append and
 * stream_filter_prepend to indicate
 * that the specified filter should only be applied when
 * reading
 */
const STREAM_FILTER_READ = 1;

/**
 * Used with stream_filter_append and
 * stream_filter_prepend to indicate
 * that the specified filter should only be applied when
 * writing
 */
const STREAM_FILTER_WRITE = 2;

/**
 * This constant is equivalent to
 * STREAM_FILTER_READ | STREAM_FILTER_WRITE
 */
const STREAM_FILTER_ALL = 3;

/**
 * Client socket opened with stream_socket_client
 * should remain persistent between page loads.
 */
const STREAM_CLIENT_PERSISTENT = 1;

/**
 * Open client socket asynchronously. This option must be used
 * together with the STREAM_CLIENT_CONNECT flag.
 * Used with stream_socket_client.
 */
const STREAM_CLIENT_ASYNC_CONNECT = 2;

/**
 * Open client socket connection. Client sockets should always
 * include this flag. Used with stream_socket_client.
 */
const STREAM_CLIENT_CONNECT = 4;

/**
 * Used with stream_socket_shutdown to disable
 * further receptions.
 * @since 5.2
 */
const STREAM_SHUT_RD = 0;

/**
 * Used with stream_socket_shutdown to disable
 * further transmissions.
 * @since 5.2
 */
const STREAM_SHUT_WR = 1;

/**
 * Used with stream_socket_shutdown to disable
 * further receptions and transmissions.
 * @since 5.2
 */
const STREAM_SHUT_RDWR = 2;

/**
 * Internet Protocol Version 4 (IPv4).
 */
const STREAM_PF_INET = 2;

/**
 * Internet Protocol Version 6 (IPv6).
 */
const STREAM_PF_INET6 = 10;

/**
 * Unix system internal protocols.
 */
const STREAM_PF_UNIX = 1;

/**
 * Provides a IP socket.
 */
const STREAM_IPPROTO_IP = 0;

/**
 * Provides a TCP socket.
 */
const STREAM_IPPROTO_TCP = 6;

/**
 * Provides a UDP socket.
 */
const STREAM_IPPROTO_UDP = 17;

/**
 * Provides a ICMP socket.
 */
const STREAM_IPPROTO_ICMP = 1;

/**
 * Provides a RAW socket.
 */
const STREAM_IPPROTO_RAW = 255;

/**
 * Provides sequenced, two-way byte streams with a transmission mechanism
 * for out-of-band data (TCP, for example).
 */
const STREAM_SOCK_STREAM = 1;

/**
 * Provides datagrams, which are connectionless messages (UDP, for
 * example).
 */
const STREAM_SOCK_DGRAM = 2;

/**
 * Provides a raw socket, which provides access to internal network
 * protocols and interfaces. Usually this type of socket is just available
 * to the root user.
 */
const STREAM_SOCK_RAW = 3;

/**
 * Provides a sequenced packet stream socket.
 */
const STREAM_SOCK_SEQPACKET = 5;

/**
 * Provides a RDM (Reliably-delivered messages) socket.
 */
const STREAM_SOCK_RDM = 4;

const STREAM_PEEK = 2;

const STREAM_OOB = 1;

/**
 * Tells a stream created with stream_socket_server
 * to bind to the specified target. Server sockets should always include this flag.
 */
const STREAM_SERVER_BIND = 4;

/**
 * Tells a stream created with stream_socket_server
 * and bound using the STREAM_SERVER_BIND flag to start
 * listening on the socket. Connection-orientated transports (such as TCP)
 * must use this flag, otherwise the server socket will not be enabled.
 * Using this flag for connect-less transports (such as UDP) is an error.
 */
const STREAM_SERVER_LISTEN = 8;

/**
 * Search for filename in include_path
 */
const FILE_USE_INCLUDE_PATH = 1;

/**
 * Strip EOL characters
 */
const FILE_IGNORE_NEW_LINES = 2;

/**
 * Skip empty lines
 */
const FILE_SKIP_EMPTY_LINES = 4;

/**
 * Append content to existing file.
 */
const FILE_APPEND = 8;

const FILE_NO_DEFAULT_CONTEXT = 16;

/**
 * This constant has no effect prior to PHP 6. It is only available for
 * forward compatibility.
 * @since 5.2
 * @deprecated 8.1
 */
const FILE_TEXT = 0;

/**
 * This constant has no effect prior to PHP 6. It is only available for
 * forward compatibility.
 * @since 5.2
 * @deprecated 8.1
 */
const FILE_BINARY = 0;

/**
 * Disable backslash escaping.
 */
const FNM_NOESCAPE = 2;

/**
 * Slash in string only matches slash in the given pattern.
 */
const FNM_PATHNAME = 1;

/**
 * Leading period in string must be exactly matched by period in the given pattern.
 */
const FNM_PERIOD = 4;

/**
 * Caseless match. Part of the GNU extension.
 */
const FNM_CASEFOLD = 16;

/**
 * Return Code indicating that the
 * userspace filter returned buckets in $out.
 */
const PSFS_PASS_ON = 2;

/**
 * Return Code indicating that the
 * userspace filter did not return buckets in $out
 * (i.e. No data available).
 */
const PSFS_FEED_ME = 1;

/**
 * Return Code indicating that the
 * userspace filter encountered an unrecoverable error
 * (i.e. Invalid data received).
 */
const PSFS_ERR_FATAL = 0;

/**
 * Regular read/write.
 */
const PSFS_FLAG_NORMAL = 0;

/**
 * An incremental flush.
 */
const PSFS_FLAG_FLUSH_INC = 1;

/**
 * Final flush prior to closing.
 */
const PSFS_FLAG_FLUSH_CLOSE = 2;

const ABDAY_1 = 131072;

const ABDAY_2 = 131073;

const ABDAY_3 = 131074;

const ABDAY_4 = 131075;

const ABDAY_5 = 131076;

const ABDAY_6 = 131077;

const ABDAY_7 = 131078;

const DAY_1 = 131079;

const DAY_2 = 131080;

const DAY_3 = 131081;

const DAY_4 = 131082;

const DAY_5 = 131083;

const DAY_6 = 131084;

const DAY_7 = 131085;

const ABMON_1 = 131086;

const ABMON_2 = 131087;

const ABMON_3 = 131088;

const ABMON_4 = 131089;

const ABMON_5 = 131090;

const ABMON_6 = 131091;

const ABMON_7 = 131092;

const ABMON_8 = 131093;

const ABMON_9 = 131094;

const ABMON_10 = 131095;

const ABMON_11 = 131096;

const ABMON_12 = 131097;

const MON_1 = 131098;

const MON_2 = 131099;

const MON_3 = 131100;

const MON_4 = 131101;

const MON_5 = 131102;

const MON_6 = 131103;

const MON_7 = 131104;

const MON_8 = 131105;

const MON_9 = 131106;

const MON_10 = 131107;

const MON_11 = 131108;

const MON_12 = 131109;

const AM_STR = 131110;

const PM_STR = 131111;

const D_T_FMT = 131112;

const D_FMT = 131113;

const T_FMT = 131114;

const T_FMT_AMPM = 131115;

const ERA = 131116;

const ERA_D_T_FMT = 131120;

const ERA_D_FMT = 131118;

const ERA_T_FMT = 131121;

const ALT_DIGITS = 131119;

const CRNCYSTR = 262159;

const RADIXCHAR = 65536;

const THOUSEP = 65537;

const YESEXPR = 327680;

const NOEXPR = 327681;

const YESSTR = 327682;

const NOSTR = 327683;

const CODESET = 14;

const CRYPT_SALT_LENGTH = 123;

const CRYPT_STD_DES = 1;

const CRYPT_EXT_DES = 1;

const CRYPT_MD5 = 1;

const CRYPT_BLOWFISH = 1;

const CRYPT_SHA256 = 1;

const CRYPT_SHA512 = 1;

const DIRECTORY_SEPARATOR = "/";

const PATH_SEPARATOR = ":";

const GLOB_BRACE = 128;

const GLOB_MARK = 8;

const GLOB_NOSORT = 32;

const GLOB_NOCHECK = 16;

const GLOB_NOESCAPE = 4096;

const GLOB_ERR = 4;

const GLOB_ONLYDIR = 1073741824;

const GLOB_AVAILABLE_FLAGS = 1073746108;

const EXTR_OVERWRITE = 0;

const EXTR_SKIP = 1;

const EXTR_PREFIX_SAME = 2;

const EXTR_PREFIX_ALL = 3;

const EXTR_PREFIX_INVALID = 4;

const EXTR_PREFIX_IF_EXISTS = 5;

const EXTR_IF_EXISTS = 6;

const EXTR_REFS = 256;

/**
 * SORT_ASC is used with
 * array_multisort to sort in ascending order.
 */
const SORT_ASC = 4;

/**
 * SORT_DESC is used with
 * array_multisort to sort in descending order.
 */
const SORT_DESC = 3;

/**
 * SORT_REGULAR is used to compare items normally.
 */
const SORT_REGULAR = 0;

/**
 * SORT_NUMERIC is used to compare items numerically.
 */
const SORT_NUMERIC = 1;

/**
 * SORT_STRING is used to compare items as strings.
 */
const SORT_STRING = 2;

/**
 * SORT_LOCALE_STRING is used to compare items as
 * strings, based on the current locale.
 * @since 5.0
 */
const SORT_LOCALE_STRING = 5;

/**
 * CASE_LOWER is used with
 * array_change_key_case and is used to convert array
 * keys to lower case. This is also the default case for
 * array_change_key_case.
 */
const CASE_LOWER = 0;

/**
 * CASE_UPPER is used with
 * array_change_key_case and is used to convert array
 * keys to upper case.
 */
const CASE_UPPER = 1;

const COUNT_NORMAL = 0;

const COUNT_RECURSIVE = 1;

const ASSERT_ACTIVE = 1;

const ASSERT_CALLBACK = 2;

const ASSERT_BAIL = 3;

const ASSERT_WARNING = 4;

/**
 * @removed 8.0
 */
const ASSERT_QUIET_EVAL = 5;

const ASSERT_EXCEPTION = 5;

/**
 * Flag indicating if the stream used the include path.
 */
const STREAM_USE_PATH = 1;

const STREAM_IGNORE_URL = 2;

const STREAM_ENFORCE_SAFE_MODE = 4;

/**
 * Flag indicating if the wrapper
 * is responsible for raising errors using trigger_error
 * during opening of the stream. If this flag is not set, you
 * should not raise any errors.
 */
const STREAM_REPORT_ERRORS = 8;

/**
 * This flag is useful when your extension really must be able to randomly
 * seek around in a stream. Some streams may not be seekable in their
 * native form, so this flag asks the streams API to check to see if the
 * stream does support seeking. If it does not, it will copy the stream
 * into temporary storage (which may be a temporary file or a memory
 * stream) which does support seeking.
 * Please note that this flag is not useful when you want to seek the
 * stream and write to it, because the stream you are accessing might
 * not be bound to the actual resource you requested.
 * If the requested resource is network based, this flag will cause the
 * opener to block until the whole contents have been downloaded.
 */
const STREAM_MUST_SEEK = 16;

const STREAM_URL_STAT_LINK = 1;

const STREAM_URL_STAT_QUIET = 2;

const STREAM_MKDIR_RECURSIVE = 1;

const STREAM_IS_URL = 1;

const STREAM_OPTION_BLOCKING = 1;

const STREAM_OPTION_READ_TIMEOUT = 4;

const STREAM_OPTION_READ_BUFFER = 2;

const STREAM_OPTION_WRITE_BUFFER = 3;

const STREAM_BUFFER_NONE = 0;

const STREAM_BUFFER_LINE = 1;

const STREAM_BUFFER_FULL = 2;

/**
 * Stream casting, when stream_cast is called
 * otherwise (see above).
 */
const STREAM_CAST_AS_STREAM = 0;

/**
 * Stream casting, for when stream_select is
 * calling stream_cast.
 */
const STREAM_CAST_FOR_SELECT = 3;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_GIF = 1;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JPEG = 2;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_PNG = 3;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_SWF = 4;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_PSD = 5;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_BMP = 6;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_TIFF_II = 7;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_TIFF_MM = 8;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JPC = 9;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JP2 = 10;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JPX = 11;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JB2 = 12;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_SWC = 13;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_IFF = 14;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_WBMP = 15;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_JPEG2000 = 9;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_XBM = 16;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 */
const IMAGETYPE_ICO = 17;

/**
 * Image type constant used by the and {@link image_type_to_extension() functions.
 * @since 7.1
 */
const IMAGETYPE_WEBP = 18;

const IMAGETYPE_UNKNOWN = 0;

const IMAGETYPE_COUNT = 22;

/**
 * @since 8.1
 */
const IMAGETYPE_AVIF = 19;

const IMAGETYPE_HEIF = 20;

const IMAGETYPE_SVG = 21;

/**
 * IPv4 Address Resource
 */
const DNS_A = 1;

const DNS_CAA = 8192;

/**
 * Authoritative Name Server Resource
 */
const DNS_NS = 2;

/**
 * Alias (Canonical Name) Resource
 */
const DNS_CNAME = 16;

/**
 * Start of Authority Resource
 */
const DNS_SOA = 32;

/**
 * Pointer Resource
 */
const DNS_PTR = 2048;

/**
 * Host Info Resource (See IANA's
 * Operating System Names
 * for the meaning of these values)
 */
const DNS_HINFO = 4096;

/**
 * Mail Exchanger Resource
 */
const DNS_MX = 16384;

/**
 * Text Resource
 */
const DNS_TXT = 32768;

const DNS_SRV = 33554432;

const DNS_NAPTR = 67108864;

/**
 * IPv6 Address Resource
 */
const DNS_AAAA = 134217728;

const DNS_A6 = 16777216;

/**
 * Any Resource Record. On most systems
 * this returns all resource records, however
 * it should not be counted upon for critical
 * uses. Try DNS_ALL instead.
 */
const DNS_ANY = 268435456;

/**
 * Iteratively query the name server for
 * each available record type.
 */
const DNS_ALL = 251721779;

/**
 * Encoding is performed per RFC 1738 and the application/x-www-form-urlencoded media type,
 * which implies that spaces are encoded as plus (+) signs.
 */
const PHP_QUERY_RFC1738 = 1;

/**
 * Encoding is performed according to RFC 3986, and spaces will be percent encoded (%20).
 */
const PHP_QUERY_RFC3986 = 2;

/**
 * Constant containing either the session name and session ID in the form of "name=ID" or
 * empty string if session ID was set in an appropriate session cookie.
 * This is the same id as the one returned by session_id().
 * @see session_id()
 */
const SID = "name=ID";

/**
 * Return value of session_status() if sessions are disabled.
 * @since 5.4
 */
const PHP_SESSION_DISABLED = 0;

/**
 * Return value of session_status() if sessions are enabled, but no session exists.
 * @since 5.4
 */
const PHP_SESSION_NONE = 1;

/**
 * Return value of session_status() if sessions are enabled, and a session exists.
 * @since 5.4
 */
const PHP_SESSION_ACTIVE = 2;

/**
 * Replace invalid code unit sequences with a Unicode Replacement Character
 * U+FFFD (UTF-8) or &#FFFD; (otherwise) instead of returning an empty string.
 * @since 5.4
 */
const ENT_SUBSTITUTE = 8;

/**
 * Replace invalid code points for the given document type with
 * a Unicode Replacement Character U+FFFD (UTF-8) or &#FFFD;
 * (otherwise) instead of leaving them as is. This may be useful,
 * for instance, to ensure the well-formedness of XML documents
 * with embedded external content.
 * @since 5.4
 */
const ENT_DISALLOWED = 128;

/**
 * Handle code as HTML 4.01.
 * @since 5.4
 */
const ENT_HTML401 = 0;

/**
 * Handle code as XML 1.
 * @since 5.4
 */
const ENT_XML1 = 16;

/**
 * Handle code as XHTML.
 * @since 5.4
 */
const ENT_XHTML = 32;

/**
 * Handle code as HTML 5.
 * @since 5.4
 */
const ENT_HTML5 = 48;

const SCANDIR_SORT_ASCENDING = 0;

const SCANDIR_SORT_DESCENDING = 1;

const SCANDIR_SORT_NONE = 2;

/**
 * SORT_NATURAL is used to compare items as strings using "natural ordering" like natsort().
 * @since 5.4
 */
const SORT_NATURAL = 6;

/**
 * SORT_FLAG_CASE can be combined (bitwise OR) with SORT_STRING or SORT_NATURAL to sort strings case-insensitively.
 * @since 5.4
 */
const SORT_FLAG_CASE = 8;

const STREAM_META_TOUCH = 1;

const STREAM_META_OWNER = 3;

const STREAM_META_OWNER_NAME = 2;

const STREAM_META_GROUP = 5;

const STREAM_META_GROUP_NAME = 4;

const STREAM_META_ACCESS = 6;

const STREAM_CRYPTO_METHOD_SSLv2_CLIENT = 3;

const STREAM_CRYPTO_METHOD_SSLv3_CLIENT = 5;

const STREAM_CRYPTO_METHOD_SSLv23_CLIENT = 57;

const STREAM_CRYPTO_METHOD_TLS_CLIENT = 121;

const STREAM_CRYPTO_METHOD_SSLv2_SERVER = 2;

const STREAM_CRYPTO_METHOD_SSLv3_SERVER = 4;

const STREAM_CRYPTO_METHOD_SSLv23_SERVER = 120;

const STREAM_CRYPTO_METHOD_TLS_SERVER = 120;

const STREAM_CRYPTO_METHOD_ANY_CLIENT = 127;

const STREAM_CRYPTO_METHOD_ANY_SERVER = 126;

const STREAM_CRYPTO_METHOD_TLSv1_0_CLIENT = 9;

const STREAM_CRYPTO_METHOD_TLSv1_0_SERVER = 8;

const STREAM_CRYPTO_METHOD_TLSv1_1_CLIENT = 17;

const STREAM_CRYPTO_METHOD_TLSv1_1_SERVER = 16;

const STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT = 33;

const STREAM_CRYPTO_METHOD_TLSv1_2_SERVER = 32;

/**
 * @since 7.4
 */
const STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT = 65;

/**
 * @since 7.4
 */
const STREAM_CRYPTO_METHOD_TLSv1_3_SERVER = 64;

const STREAM_CRYPTO_PROTO_SSLv3 = 4;

const STREAM_CRYPTO_PROTO_TLSv1_0 = 8;

const STREAM_CRYPTO_PROTO_TLSv1_1 = 16;

const STREAM_CRYPTO_PROTO_TLSv1_2 = 32;

/**
 * @since 7.4
 */
const STREAM_CRYPTO_PROTO_TLSv1_3 = 64;

/**
 * @since 7.1
 */
const MT_RAND_MT19937 = 0;

/**
 * @since 7.1
 * @deprecated 8.3
 */
const MT_RAND_PHP = 1;

/**
 * system is unusable
 */
const LOG_EMERG = 0;

/**
 * action must be taken immediately
 */
const LOG_ALERT = 1;

/**
 * critical conditions
 */
const LOG_CRIT = 2;

/**
 * error conditions
 */
const LOG_ERR = 3;

/**
 * warning conditions
 */
const LOG_WARNING = 4;

/**
 * normal, but significant, condition
 */
const LOG_NOTICE = 5;

/**
 * informational message
 */
const LOG_INFO = 6;

/**
 * debug-level message
 */
const LOG_DEBUG = 7;

/**
 * kernel messages
 */
const LOG_KERN = 0;

/**
 * generic user-level messages
 */
const LOG_USER = 8;

/**
 * mail subsystem
 */
const LOG_MAIL = 16;

/**
 * other system daemons
 */
const LOG_DAEMON = 24;

/**
 * security/authorization messages (use LOG_AUTHPRIV instead
 * in systems where that constant is defined)
 */
const LOG_AUTH = 32;

/**
 * messages generated internally by syslogd
 */
const LOG_SYSLOG = 40;

/**
 * line printer subsystem
 */
const LOG_LPR = 48;

/**
 * USENET news subsystem
 */
const LOG_NEWS = 56;

/**
 * UUCP subsystem
 */
const LOG_UUCP = 64;

/**
 * clock daemon (cron and at)
 */
const LOG_CRON = 72;

/**
 * security/authorization messages (private)
 */
const LOG_AUTHPRIV = 80;

const LOG_LOCAL0 = 128;

const LOG_LOCAL1 = 136;

const LOG_LOCAL2 = 144;

const LOG_LOCAL3 = 152;

const LOG_LOCAL4 = 160;

const LOG_LOCAL5 = 168;

const LOG_LOCAL6 = 176;

const LOG_LOCAL7 = 184;

/**
 * include PID with each message
 */
const LOG_PID = 1;

/**
 * if there is an error while sending data to the system logger,
 * write directly to the system console
 */
const LOG_CONS = 2;

/**
 * (default) delay opening the connection until the first
 * message is logged
 */
const LOG_ODELAY = 4;

/**
 * open the connection to the logger immediately
 */
const LOG_NDELAY = 8;

const LOG_NOWAIT = 16;

/**
 * print log message also to standard error
 */
const LOG_PERROR = 32;

/**
 * @since 8.2
 */
const DECIMAL_POINT = 65536;

/**
 * @since 8.2
 */
const THOUSANDS_SEP = 65537;

/**
 * @since 8.2
 */
const GROUPING = 65538;

/**
 * @since 8.2
 */
const ERA_YEAR = 131117;

/**
 * @since 8.2
 */
const INT_CURR_SYMBOL = 262144;

/**
 * @since 8.2
 */
const CURRENCY_SYMBOL = 262145;

/**
 * @since 8.2
 */
const MON_DECIMAL_POINT = 262146;

/**
 * @since 8.2
 */
const MON_THOUSANDS_SEP = 262147;

/**
 * @since 8.2
 */
const MON_GROUPING = 262148;

/**
 * @since 8.2
 */
const POSITIVE_SIGN = 262149;

/**
 * @since 8.2
 */
const NEGATIVE_SIGN = 262150;

/**
 * @since 8.2
 */
const INT_FRAC_DIGITS = 262151;

/**
 * @since 8.2
 */
const FRAC_DIGITS = 262152;

/**
 * @since 8.2
 */
const P_CS_PRECEDES = 262153;

/**
 * @since 8.2
 */
const P_SEP_BY_SPACE = 262154;

/**
 * @since 8.2
 */
const N_CS_PRECEDES = 262155;

/**
 * @since 8.2
 */
const N_SEP_BY_SPACE = 262156;

/**
 * @since 8.2
 */
const P_SIGN_POSN = 262157;

/**
 * @since 8.2
 */
const N_SIGN_POSN = 262158;
