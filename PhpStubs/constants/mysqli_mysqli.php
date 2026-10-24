<?php

/**
 * Read options from the named group from my.cnf
 * or the file specified with MYSQLI_READ_DEFAULT_FILE
 */
const MYSQLI_READ_DEFAULT_GROUP = 5;

/**
 * Read options from the named option file instead of from my.cnf
 */
const MYSQLI_READ_DEFAULT_FILE = 4;

/**
 * Connect timeout in seconds
 */
const MYSQLI_OPT_CONNECT_TIMEOUT = 0;

/**
 * Enables command LOAD LOCAL INFILE
 */
const MYSQLI_OPT_LOCAL_INFILE = 8;

/**
 * RSA public key file used with the SHA-256 based authentication.
 */
const MYSQLI_SERVER_PUBLIC_KEY = 35;

/**
 * Command to execute when connecting to MySQL server. Will automatically be re-executed when reconnecting.
 */
const MYSQLI_INIT_COMMAND = 3;

const MYSQLI_OPT_NET_CMD_BUFFER_SIZE = 202;

const MYSQLI_OPT_NET_READ_BUFFER_SIZE = 203;

const MYSQLI_OPT_INT_AND_FLOAT_NATIVE = 201;

/**
 * Use SSL (encrypted protocol). This option should not be set by application programs;
 * it is set internally in the MySQL client library
 */
const MYSQLI_CLIENT_SSL = 2048;

/**
 * Use compression protocol
 */
const MYSQLI_CLIENT_COMPRESS = 32;

/**
 * Allow interactive_timeout seconds
 * (instead of wait_timeout seconds) of inactivity before
 * closing the connection. The client's session
 * wait_timeout variable will be set to
 * the value of the session interactive_timeout variable.
 */
const MYSQLI_CLIENT_INTERACTIVE = 1024;

/**
 * Allow spaces after function names. Makes all functions names reserved words.
 */
const MYSQLI_CLIENT_IGNORE_SPACE = 256;

/**
 * Don't allow the db_name.tbl_name.col_name syntax.
 */
const MYSQLI_CLIENT_NO_SCHEMA = 16;

const MYSQLI_CLIENT_FOUND_ROWS = 2;

/**
 * For using buffered resultsets
 */
const MYSQLI_STORE_RESULT = 0;

/**
 * For using unbuffered resultsets
 */
const MYSQLI_USE_RESULT = 1;

const MYSQLI_ASYNC = 8;

/**
 * Columns are returned into the array having the fieldname as the array index.
 */
const MYSQLI_ASSOC = 1;

/**
 * Columns are returned into the array having an enumerated index.
 */
const MYSQLI_NUM = 2;

/**
 * Columns are returned into the array having both a numerical index and the fieldname as the associative index.
 */
const MYSQLI_BOTH = 3;

const MYSQLI_STMT_ATTR_UPDATE_MAX_LENGTH = 0;

const MYSQLI_STMT_ATTR_CURSOR_TYPE = 1;

const MYSQLI_CURSOR_TYPE_NO_CURSOR = 0;

const MYSQLI_CURSOR_TYPE_READ_ONLY = 1;

const MYSQLI_CURSOR_TYPE_FOR_UPDATE = 2;

const MYSQLI_CURSOR_TYPE_SCROLLABLE = 4;

const MYSQLI_STMT_ATTR_PREFETCH_ROWS = 2;

/**
 * Indicates that a field is defined as NOT NULL
 */
const MYSQLI_NOT_NULL_FLAG = 1;

/**
 * Field is part of a primary index
 */
const MYSQLI_PRI_KEY_FLAG = 2;

/**
 * Field is part of a unique index.
 */
const MYSQLI_UNIQUE_KEY_FLAG = 4;

/**
 * Field is part of an index.
 */
const MYSQLI_MULTIPLE_KEY_FLAG = 8;

/**
 * Field is defined as BLOB
 */
const MYSQLI_BLOB_FLAG = 16;

/**
 * Field is defined as UNSIGNED
 */
const MYSQLI_UNSIGNED_FLAG = 32;

/**
 * Field is defined as ZEROFILL
 */
const MYSQLI_ZEROFILL_FLAG = 64;

/**
 * Field is defined as AUTO_INCREMENT
 */
const MYSQLI_AUTO_INCREMENT_FLAG = 512;

/**
 * Field is defined as TIMESTAMP
 */
const MYSQLI_TIMESTAMP_FLAG = 1024;

/**
 * Field is defined as SET
 */
const MYSQLI_SET_FLAG = 2048;

/**
 * Field is defined as NUMERIC
 */
const MYSQLI_NUM_FLAG = 32768;

/**
 * Field is part of an multi-index
 */
const MYSQLI_PART_KEY_FLAG = 16384;

/**
 * Field is part of GROUP BY
 */
const MYSQLI_GROUP_FLAG = 32768;

/**
 * Field is defined as ENUM. Available since PHP 5.3.0.
 */
const MYSQLI_ENUM_FLAG = 256;

const MYSQLI_BINARY_FLAG = 128;

const MYSQLI_NO_DEFAULT_VALUE_FLAG = 4096;

const MYSQLI_ON_UPDATE_NOW_FLAG = 8192;

const MYSQLI_TRANS_START_READ_ONLY = 4;

const MYSQLI_TRANS_START_READ_WRITE = 2;

const MYSQLI_TRANS_START_WITH_CONSISTENT_SNAPSHOT = 1;

/**
 * Field is defined as DECIMAL
 */
const MYSQLI_TYPE_DECIMAL = 0;

/**
 * Field is defined as TINYINT
 */
const MYSQLI_TYPE_TINY = 1;

/**
 * Field is defined as SMALLINT
 */
const MYSQLI_TYPE_SHORT = 2;

/**
 * Field is defined as INT
 */
const MYSQLI_TYPE_LONG = 3;

/**
 * Field is defined as FLOAT
 */
const MYSQLI_TYPE_FLOAT = 4;

/**
 * Field is defined as DOUBLE
 */
const MYSQLI_TYPE_DOUBLE = 5;

/**
 * Field is defined as DEFAULT NULL
 */
const MYSQLI_TYPE_NULL = 6;

/**
 * Field is defined as TIMESTAMP
 */
const MYSQLI_TYPE_TIMESTAMP = 7;

/**
 * Field is defined as BIGINT
 */
const MYSQLI_TYPE_LONGLONG = 8;

/**
 * Field is defined as MEDIUMINT
 */
const MYSQLI_TYPE_INT24 = 9;

/**
 * Field is defined as DATE
 */
const MYSQLI_TYPE_DATE = 10;

/**
 * Field is defined as TIME
 */
const MYSQLI_TYPE_TIME = 11;

/**
 * Field is defined as DATETIME
 */
const MYSQLI_TYPE_DATETIME = 12;

/**
 * Field is defined as YEAR
 */
const MYSQLI_TYPE_YEAR = 13;

/**
 * Field is defined as DATE
 */
const MYSQLI_TYPE_NEWDATE = 14;

/**
 * Field is defined as ENUM
 */
const MYSQLI_TYPE_ENUM = 247;

/**
 * Field is defined as SET
 */
const MYSQLI_TYPE_SET = 248;

/**
 * Field is defined as TINYBLOB
 */
const MYSQLI_TYPE_TINY_BLOB = 249;

/**
 * Field is defined as MEDIUMBLOB
 */
const MYSQLI_TYPE_MEDIUM_BLOB = 250;

/**
 * Field is defined as LONGBLOB
 */
const MYSQLI_TYPE_LONG_BLOB = 251;

/**
 * Field is defined as BLOB
 */
const MYSQLI_TYPE_BLOB = 252;

/**
 * Field is defined as VARCHAR
 */
const MYSQLI_TYPE_VAR_STRING = 253;

/**
 * Field is defined as STRING
 */
const MYSQLI_TYPE_STRING = 254;

/**
 * Field is defined as CHAR
 */
const MYSQLI_TYPE_CHAR = 1;

/**
 * Field is defined as INTERVAL
 */
const MYSQLI_TYPE_INTERVAL = 247;

/**
 * Field is defined as GEOMETRY
 */
const MYSQLI_TYPE_GEOMETRY = 255;

/**
 * Precision math DECIMAL or NUMERIC field (MySQL 5.0.3 and up)
 */
const MYSQLI_TYPE_NEWDECIMAL = 246;

/**
 * Field is defined as BIT (MySQL 5.0.3 and up)
 */
const MYSQLI_TYPE_BIT = 16;

const MYSQLI_SET_CHARSET_NAME = 7;

/**
 * No more data available for bind variable
 */
const MYSQLI_NO_DATA = 100;

/**
 * Data truncation occurred. Available since PHP 5.1.0 and MySQL 5.0.5.
 */
const MYSQLI_DATA_TRUNCATED = 101;

/**
 * Report if no index or bad index was used in a query.
 */
const MYSQLI_REPORT_INDEX = 4;

/**
 * Report errors from mysqli function calls.
 */
const MYSQLI_REPORT_ERROR = 1;

/**
 * Throw a mysqli_sql_exception for errors instead of warnings.
 */
const MYSQLI_REPORT_STRICT = 2;

/**
 * Set all options on (report all).
 */
const MYSQLI_REPORT_ALL = 255;

/**
 * Turns reporting off.
 */
const MYSQLI_REPORT_OFF = 0;

/**
 * Is set to 1 if mysqli_debug functionality is enabled.
 */
const MYSQLI_DEBUG_TRACE_ENABLED = 0;

const MYSQLI_SERVER_QUERY_NO_GOOD_INDEX_USED = 16;

const MYSQLI_SERVER_QUERY_NO_INDEX_USED = 32;

const MYSQLI_REFRESH_GRANT = 1;

const MYSQLI_REFRESH_LOG = 2;

const MYSQLI_REFRESH_TABLES = 4;

const MYSQLI_REFRESH_HOSTS = 8;

const MYSQLI_REFRESH_STATUS = 16;

const MYSQLI_REFRESH_THREADS = 32;

const MYSQLI_REFRESH_SLAVE = 64;

const MYSQLI_REFRESH_MASTER = 128;

const MYSQLI_SERVER_QUERY_WAS_SLOW = 2048;

const MYSQLI_REFRESH_BACKUP_LOG = 2097152;

const MYSQLI_OPT_SSL_VERIFY_SERVER_CERT = 21;

const MYSQLI_SET_CHARSET_DIR = 6;

const MYSQLI_SERVER_PS_OUT_PARAMS = 4096;

const MYSQLI_CLIENT_SSL_VERIFY_SERVER_CERT = 1073741824;

const MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT = 64;

const MYSQLI_CLIENT_CAN_HANDLE_EXPIRED_PASSWORDS = 4194304;

const MYSQLI_OPT_CAN_HANDLE_EXPIRED_PASSWORDS = 37;

const MYSQLI_OPT_READ_TIMEOUT = 11;

/**
 * @deprecated 8.4
 */
const MYSQLI_STORE_RESULT_COPY_DATA = 16;

const MYSQLI_TYPE_JSON = 245;

const MYSQLI_TRANS_COR_AND_CHAIN = 1;

const MYSQLI_TRANS_COR_AND_NO_CHAIN = 2;

const MYSQLI_TRANS_COR_RELEASE = 4;

const MYSQLI_TRANS_COR_NO_RELEASE = 8;

const MYSQLI_OPT_LOAD_DATA_LOCAL_DIR = 43;

const MYSQLI_REFRESH_REPLICA = 64;

/**
 * @since 8.1
 */
const MYSQLI_IS_MARIADB = 0;

/**
 * @since 8.4
 */
const MYSQLI_TYPE_VECTOR = 242;

/**
 * @since 8.6
 */
const MYSQLI_OPT_COMPRESS = 1;
