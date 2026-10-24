<?php

/**
 * Represents a connection between PHP and a database server.
 */
class PDO
{
    /**
     * Represents the SQL NULL data type.
     */
    public const PARAM_NULL = 0;

    /**
     * Represents the SQL INTEGER data type.
     */
    public const PARAM_INT = 1;

    /**
     * Represents the SQL CHAR, VARCHAR, or other string data type.
     */
    public const PARAM_STR = 2;

    /**
     * Represents the SQL large object data type.
     */
    public const PARAM_LOB = 3;

    /**
     * Represents a recordset type. Not currently supported by any drivers.
     */
    public const PARAM_STMT = 4;

    /**
     * Represents a boolean data type.
     */
    public const PARAM_BOOL = 5;

    /**
     * Flag to denote a string uses the national character set.
     * @since 7.2
     */
    public const PARAM_STR_NATL = 1073741824;

    /**
     * Flag to denote a string uses the regular character set.
     * @since 7.2
     */
    public const PARAM_STR_CHAR = 536870912;

    /**
     * Sets the default string parameter type, this can be one of PDO::PARAM_STR_NATL and PDO::PARAM_STR_CHAR.
     * @since 7.2
     */
    public const ATTR_DEFAULT_STR_PARAM = 21;

    /**
     * Specifies that a function created with PDO::sqliteCreateFunction() is deterministic, i.e. it always returns the same result given the same inputs within a single SQL statement.
     * @since 7.1
     */
    public const SQLITE_DETERMINISTIC = 2048;

    /**
     * @since 7.3
     */
    public const SQLITE_OPEN_READONLY = 1;

    /**
     * @since 7.3
     */
    public const SQLITE_OPEN_READWRITE = 2;

    /**
     * @since 7.3
     */
    public const SQLITE_OPEN_CREATE = 4;

    /**
     * @since 7.3
     */
    public const SQLITE_ATTR_OPEN_FLAGS = 1000;

    /**
     * Specifies that the parameter is an INOUT parameter for a stored
     * procedure. You must bitwise-OR this value with an explicit
     * PDO::PARAM_* data type.
     */
    public const PARAM_INPUT_OUTPUT = 2147483648;

    /**
     * Allocation event
     */
    public const PARAM_EVT_ALLOC = 0;

    /**
     * Deallocation event
     */
    public const PARAM_EVT_FREE = 1;

    /**
     * Event triggered prior to execution of a prepared statement.
     */
    public const PARAM_EVT_EXEC_PRE = 2;

    /**
     * Event triggered subsequent to execution of a prepared statement.
     */
    public const PARAM_EVT_EXEC_POST = 3;

    /**
     * Event triggered prior to fetching a result from a resultset.
     */
    public const PARAM_EVT_FETCH_PRE = 4;

    /**
     * Event triggered subsequent to fetching a result from a resultset.
     */
    public const PARAM_EVT_FETCH_POST = 5;

    /**
     * Event triggered during bound parameter registration
     * allowing the driver to normalize the parameter name.
     */
    public const PARAM_EVT_NORMALIZE = 6;

    /**
     * Specifies that the fetch method shall return each row as an object with
     * variable names that correspond to the column names returned in the result
     * set. PDO::FETCH_LAZY creates the object variable names as they are accessed.
     * Not valid inside PDOStatement::fetchAll.
     */
    public const FETCH_LAZY = 1;

    /**
     * Specifies that the fetch method shall return each row as an array indexed
     * by column name as returned in the corresponding result set. If the result
     * set contains multiple columns with the same name,
     * PDO::FETCH_ASSOC returns
     * only a single value per column name.
     */
    public const FETCH_ASSOC = 2;

    /**
     * Specifies that the fetch method shall return each row as an array indexed
     * by column number as returned in the corresponding result set, starting at
     * column 0.
     */
    public const FETCH_NUM = 3;

    /**
     * Specifies that the fetch method shall return each row as an array indexed
     * by both column name and number as returned in the corresponding result set,
     * starting at column 0.
     */
    public const FETCH_BOTH = 4;

    /**
     * Specifies that the fetch method shall return each row as an object with
     * property names that correspond to the column names returned in the result
     * set.
     */
    public const FETCH_OBJ = 5;

    /**
     * Specifies that the fetch method shall return TRUE and assign the values of
     * the columns in the result set to the PHP variables to which they were
     * bound with the PDOStatement::bindParam or
     * PDOStatement::bindColumn methods.
     */
    public const FETCH_BOUND = 6;

    /**
     * Specifies that the fetch method shall return only a single requested
     * column from the next row in the result set.
     */
    public const FETCH_COLUMN = 7;

    /**
     * Specifies that the fetch method shall return a new instance of the
     * requested class, mapping the columns to named properties in the class.
     * The magic
     * __set
     * method is called if the property doesn't exist in the requested class
     */
    public const FETCH_CLASS = 8;

    /**
     * Specifies that the fetch method shall update an existing instance of the
     * requested class, mapping the columns to named properties in the class.
     */
    public const FETCH_INTO = 9;

    /**
     * Allows completely customize the way data is treated on the fly (only
     * valid inside PDOStatement::fetchAll).
     */
    public const FETCH_FUNC = 10;

    /**
     * Group return by values. Usually combined with
     * PDO::FETCH_COLUMN or
     * PDO::FETCH_KEY_PAIR.
     */
    public const FETCH_GROUP = 32;

    /**
     * Fetch only the unique values.
     */
    public const FETCH_UNIQUE = 64;

    /**
     * Fetch a two-column result into an array where the first column is a key and the second column
     * is the value.
     * @since 5.2
     */
    public const FETCH_KEY_PAIR = 12;

    /**
     * Determine the class name from the value of first column.
     */
    public const FETCH_CLASSTYPE = 128;

    /**
     * As PDO::FETCH_INTO but object is provided as a serialized string.
     * Available since PHP 5.1.0. Since PHP 5.3.0 the class constructor is never called if this
     * flag is set.
     */
    public const FETCH_SERIALIZE = 512;

    /**
     * Call the constructor before setting properties.
     * @since 5.2
     */
    public const FETCH_PROPS_LATE = 256;

    /**
     * Specifies that the fetch method shall return each row as an array indexed
     * by column name as returned in the corresponding result set. If the result
     * set contains multiple columns with the same name,
     * PDO::FETCH_NAMED returns
     * an array of values per column name.
     */
    public const FETCH_NAMED = 11;

    /**
     * If this value is FALSE, PDO attempts to disable autocommit so that the
     * connection begins a transaction.
     */
    public const ATTR_AUTOCOMMIT = 0;

    /**
     * Setting the prefetch size allows you to balance speed against memory
     * usage for your application. Not all database/driver combinations support
     * setting of the prefetch size. A larger prefetch size results in
     * increased performance at the cost of higher memory usage.
     */
    public const ATTR_PREFETCH = 1;

    /**
     * Sets the timeout value in seconds for communications with the database.
     */
    public const ATTR_TIMEOUT = 2;

    public const ATTR_ERRMODE = 3;

    /**
     * This is a read only attribute; it will return information about the
     * version of the database server to which PDO is connected.
     */
    public const ATTR_SERVER_VERSION = 4;

    /**
     * This is a read only attribute; it will return information about the
     * version of the client libraries that the PDO driver is using.
     */
    public const ATTR_CLIENT_VERSION = 5;

    /**
     * This is a read only attribute; it will return some meta information about the
     * database server to which PDO is connected.
     */
    public const ATTR_SERVER_INFO = 6;

    public const ATTR_CONNECTION_STATUS = 7;

    /**
     * Force column names to a specific case specified by the PDO::CASE_*
     * constants.
     */
    public const ATTR_CASE = 8;

    /**
     * Get or set the name to use for a cursor. Most useful when using
     * scrollable cursors and positioned updates.
     */
    public const ATTR_CURSOR_NAME = 9;

    /**
     * Selects the cursor type. PDO currently supports either
     * PDO::CURSOR_FWDONLY and
     * PDO::CURSOR_SCROLL. Stick with
     * PDO::CURSOR_FWDONLY unless you know that you need a
     * scrollable cursor.
     */
    public const ATTR_CURSOR = 10;

    /**
     * Convert empty strings to SQL NULL values on data fetches.
     */
    public const ATTR_ORACLE_NULLS = 11;

    /**
     * Request a persistent connection, rather than creating a new connection.
     */
    public const ATTR_PERSISTENT = 12;

    /**
     * Sets the class name of which statements are returned as.
     */
    public const ATTR_STATEMENT_CLASS = 13;

    /**
     * Prepend the containing table name to each column name returned in the
     * result set. The table name and column name are separated by a decimal (.)
     * character. Support of this attribute is at the driver level; it may not
     * be supported by your driver.
     */
    public const ATTR_FETCH_TABLE_NAMES = 14;

    /**
     * Prepend the containing catalog name to each column name returned in the
     * result set. The catalog name and column name are separated by a decimal
     * (.) character. Support of this attribute is at the driver level; it may
     * not be supported by your driver.
     */
    public const ATTR_FETCH_CATALOG_NAMES = 15;

    /**
     * Returns the name of the driver.
     *
     * using PDO::ATTR_DRIVER_NAME
     *
     * if (\$db->getAttribute(PDO::ATTR_DRIVER_NAME) == 'mysql') {
     * echo "Running on mysql; doing something mysql specific here\n";
     * }
     */
    public const ATTR_DRIVER_NAME = 16;

    /**
     * Forces all values fetched to be treated as strings.
     */
    public const ATTR_STRINGIFY_FETCHES = 17;

    /**
     * Sets the maximum column name length.
     */
    public const ATTR_MAX_COLUMN_LEN = 18;

    /**
     * @since 5.1
     */
    public const ATTR_EMULATE_PREPARES = 20;

    /**
     * @since 5.2
     */
    public const ATTR_DEFAULT_FETCH_MODE = 19;

    /**
     * Do not raise an error or exception if an error occurs. The developer is
     * expected to explicitly check for errors. This is the default mode.
     */
    public const ERRMODE_SILENT = 0;

    /**
     * Issue a PHP E_WARNING message if an error occurs.
     */
    public const ERRMODE_WARNING = 1;

    /**
     * Throw a PDOException if an error occurs.
     */
    public const ERRMODE_EXCEPTION = 2;

    /**
     * Leave column names as returned by the database driver.
     */
    public const CASE_NATURAL = 0;

    /**
     * Force column names to lower case.
     */
    public const CASE_LOWER = 2;

    /**
     * Force column names to upper case.
     */
    public const CASE_UPPER = 1;

    public const NULL_NATURAL = 0;

    public const NULL_EMPTY_STRING = 1;

    public const NULL_TO_STRING = 2;

    /**
     * Corresponds to SQLSTATE '00000', meaning that the SQL statement was
     * successfully issued with no errors or warnings. This constant is for
     * your convenience when checking PDO::errorCode or
     * PDOStatement::errorCode to determine if an error
     * occurred. You will usually know if this is the case by examining the
     * return code from the method that raised the error condition anyway.
     */
    public const ERR_NONE = '00000';

    /**
     * Fetch the next row in the result set. Valid only for scrollable cursors.
     */
    public const FETCH_ORI_NEXT = 0;

    /**
     * Fetch the previous row in the result set. Valid only for scrollable
     * cursors.
     */
    public const FETCH_ORI_PRIOR = 1;

    /**
     * Fetch the first row in the result set. Valid only for scrollable cursors.
     */
    public const FETCH_ORI_FIRST = 2;

    /**
     * Fetch the last row in the result set. Valid only for scrollable cursors.
     */
    public const FETCH_ORI_LAST = 3;

    /**
     * Fetch the requested row by row number from the result set. Valid only
     * for scrollable cursors.
     */
    public const FETCH_ORI_ABS = 4;

    /**
     * Fetch the requested row by relative position from the current position
     * of the cursor in the result set. Valid only for scrollable cursors.
     */
    public const FETCH_ORI_REL = 5;

    /**
     * Specifies that the default fetch mode shall be used.
     * @since 8.0
     */
    public const FETCH_DEFAULT = 0;

    /**
     * Create a PDOStatement object with a forward-only cursor. This is the
     * default cursor choice, as it is the fastest and most common data access
     * pattern in PHP.
     */
    public const CURSOR_FWDONLY = 0;

    /**
     * Create a PDOStatement object with a scrollable cursor. Pass the
     * PDO::FETCH_ORI_* constants to control the rows fetched from the result set.
     */
    public const CURSOR_SCROLL = 1;

    /**
     * If this attribute is set to TRUE on a
     * PDOStatement, the MySQL driver will use the
     * buffered versions of the MySQL API. If you're writing portable code, you
     * should use PDOStatement::fetchAll instead.
     *
     * Forcing queries to be buffered in mysql
     *
     * if (\$db->getAttribute(PDO::ATTR_DRIVER_NAME) == 'mysql') {
     * \$stmt = \$db->prepare('select * from foo',
     * array(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY => true));
     * } else {
     * die("my application only works with mysql; I should use \\$stmt->fetchAll() instead");
     * }
     */
    public const MYSQL_ATTR_USE_BUFFERED_QUERY = 1000;

    /**
     * Enable LOAD LOCAL INFILE.
     *
     * Note, this constant can only be used in the driver_options
     * array when constructing a new database handle.
     */
    public const MYSQL_ATTR_LOCAL_INFILE = 1001;

    /**
     * Command to execute when connecting to the MySQL server. Will
     * automatically be re-executed when reconnecting.
     *
     * Note, this constant can only be used in the driver_options
     * array when constructing a new database handle.
     */
    public const MYSQL_ATTR_INIT_COMMAND = 1002;

    /**
     * Maximum buffer size. Defaults to 1 MiB. This constant is not supported when
     * compiled against mysqlnd.
     */
    public const MYSQL_ATTR_MAX_BUFFER_SIZE = 1005;

    /**
     * Read options from the named option file instead of from
     * my.cnf. This option is not available if
     * mysqlnd is used, because mysqlnd does not read the mysql
     * configuration files.
     */
    public const MYSQL_ATTR_READ_DEFAULT_FILE = 1003;

    /**
     * Read options from the named group from my.cnf or the
     * file specified with MYSQL_READ_DEFAULT_FILE. This option
     * is not available if mysqlnd is used, because mysqlnd does not read the mysql
     * configuration files.
     */
    public const MYSQL_ATTR_READ_DEFAULT_GROUP = 1004;

    /**
     * Enable network communication compression. This is not supported when
     * compiled against mysqlnd.
     */
    public const MYSQL_ATTR_COMPRESS = 1003;

    /**
     * Perform direct queries, don't use prepared statements.
     */
    public const MYSQL_ATTR_DIRECT_QUERY = 20;

    /**
     * Return the number of found (matched) rows, not the
     * number of changed rows.
     */
    public const MYSQL_ATTR_FOUND_ROWS = 1004;

    /**
     * Permit spaces after function names. Makes all functions
     * names reserved words.
     */
    public const MYSQL_ATTR_IGNORE_SPACE = 1005;

    public const MYSQL_ATTR_SERVER_PUBLIC_KEY = 1011;

    /**
     * The file path to the SSL key.
     * @since 5.3
     */
    public const MYSQL_ATTR_SSL_KEY = 1006;

    /**
     * The file path to the SSL certificate.
     * @since 5.3
     */
    public const MYSQL_ATTR_SSL_CERT = 1007;

    /**
     * The file path to the SSL certificate authority.
     * @since 5.3
     */
    public const MYSQL_ATTR_SSL_CA = 1008;

    /**
     * The file path to the directory that contains the trusted SSL
     * CA certificates, which are stored in PEM format.
     * @since 5.3
     */
    public const MYSQL_ATTR_SSL_CAPATH = 1009;

    /**
     * A list of one or more permissible ciphers to use for SSL encryption,
     * in a format understood by OpenSSL.
     * For example: DHE-RSA-AES256-SHA:AES128-SHA
     * @since 5.3
     */
    public const MYSQL_ATTR_SSL_CIPHER = 1010;

    /**
     * Disables multi query execution in both PDO::prepare() and PDO::query() when set to FALSE.
     *
     * Note, this constant can only be used in the driver_options array when constructing a new database handle.
     * @since 5.5
     */
    public const MYSQL_ATTR_MULTI_STATEMENTS = 1012;

    /**
     * Disables SSL peer verification when set to FALSE.
     * @since 7.0
     * @since 7.1
     */
    public const MYSQL_ATTR_SSL_VERIFY_SERVER_CERT = 1013;

    /**
     * @since 8.1
     */
    public const MYSQL_ATTR_LOCAL_INFILE_DIRECTORY = 1014;

    /**
     * @deprecated
     */
    public const PGSQL_ASSOC = 1;

    /**
     * @removed 7.1
     */
    public const PGSQL_ATTR_DISABLE_NATIVE_PREPARED_STATEMENT = 1000;

    /**
     * @since 5.6
     */
    public const PGSQL_ATTR_DISABLE_PREPARES = 1000;

    public const PGSQL_BAD_RESPONSE = 5;

    public const PGSQL_BOTH = 3;

    public const PGSQL_TRANSACTION_IDLE = 0;

    public const PGSQL_TRANSACTION_ACTIVE = 1;

    public const PGSQL_TRANSACTION_INTRANS = 2;

    public const PGSQL_TRANSACTION_INERROR = 3;

    public const PGSQL_TRANSACTION_UNKNOWN = 4;

    public const PGSQL_CONNECT_ASYNC = 4;

    public const PGSQL_CONNECT_FORCE_NEW = 2;

    public const PGSQL_CONNECTION_AUTH_OK = 5;

    public const PGSQL_CONNECTION_AWAITING_RESPONSE = 4;

    public const PGSQL_CONNECTION_BAD = 1;

    public const PGSQL_CONNECTION_OK = 0;

    public const PGSQL_CONNECTION_MADE = 3;

    public const PGSQL_CONNECTION_SETENV = 6;

    public const PGSQL_CONNECTION_SSL_STARTUP = 7;

    public const PGSQL_CONNECTION_STARTED = 2;

    public const PGSQL_COMMAND_OK = 1;

    public const PGSQL_CONV_FORCE_NULL = 4;

    public const PGSQL_CONV_IGNORE_DEFAULT = 2;

    public const PGSQL_CONV_IGNORE_NOT_NULL = 8;

    public const PGSQL_COPY_IN = 4;

    public const PGSQL_COPY_OUT = 3;

    public const PGSQL_DIAG_CONTEXT = 87;

    public const PGSQL_DIAG_INTERNAL_POSITION = 112;

    public const PGSQL_DIAG_INTERNAL_QUERY = 113;

    public const PGSQL_DIAG_MESSAGE_DETAIL = 68;

    public const PGSQL_DIAG_MESSAGE_HINT = 72;

    public const PGSQL_DIAG_MESSAGE_PRIMARY = 77;

    public const PGSQL_DIAG_SEVERITY = 83;

    public const PGSQL_DIAG_SOURCE_FILE = 70;

    public const PGSQL_DIAG_SOURCE_FUNCTION = 82;

    public const PGSQL_DIAG_SOURCE_LINE = 76;

    public const PGSQL_DIAG_SQLSTATE = 67;

    public const PGSQL_DIAG_STATEMENT_POSITION = 80;

    public const PGSQL_DML_ASYNC = 1024;

    public const PGSQL_DML_EXEC = 512;

    public const PGSQL_DML_NO_CONV = 256;

    public const PGSQL_DML_STRING = 2048;

    public const PGSQL_DML_ESCAPE = 4096;

    public const PGSQL_EMPTY_QUERY = 0;

    public const PGSQL_ERRORS_DEFAULT = 1;

    public const PGSQL_ERRORS_TERSE = 0;

    public const PGSQL_ERRORS_VERBOSE = 2;

    public const PGSQL_FATAL_ERROR = 7;

    public const PGSQL_NONFATAL_ERROR = 6;

    public const PGSQL_NOTICE_ALL = 2;

    public const PGSQL_NOTICE_CLEAR = 3;

    public const PGSQL_NOTICE_LAST = 1;

    public const PGSQL_NUM = 2;

    public const PGSQL_POLLING_ACTIVE = 4;

    public const PGSQL_POLLING_FAILED = 0;

    public const PGSQL_POLLING_OK = 3;

    public const PGSQL_POLLING_READING = 1;

    public const PGSQL_POLLING_WRITING = 2;

    public const PGSQL_SEEK_CUR = 1;

    public const PGSQL_SEEK_END = 2;

    public const PGSQL_SEEK_SET = 0;

    public const PGSQL_STATUS_LONG = 1;

    public const PGSQL_STATUS_STRING = 2;

    public const PGSQL_TUPLES_OK = 2;

    public const SQLSRV_TXN_READ_UNCOMMITTED = "READ_UNCOMMITTED";

    public const SQLSRV_TXN_READ_COMMITTED = "READ_COMMITTED";

    public const SQLSRV_TXN_REPEATABLE_READ = "REPEATABLE_READ";

    public const SQLSRV_TXN_SNAPSHOT = "SNAPSHOT";

    public const SQLSRV_TXN_SERIALIZABLE = "SERIALIZABLE";

    public const SQLSRV_ENCODING_BINARY = 2;

    public const SQLSRV_ENCODING_SYSTEM = 3;

    public const SQLSRV_ENCODING_UTF8 = 65001;

    public const SQLSRV_ENCODING_DEFAULT = 1;

    public const SQLSRV_ATTR_ENCODING = 1000;

    public const SQLSRV_ATTR_QUERY_TIMEOUT = 1001;

    public const SQLSRV_ATTR_DIRECT_QUERY = 1002;

    public const SQLSRV_ATTR_CURSOR_SCROLL_TYPE = 1003;

    public const SQLSRV_ATTR_CLIENT_BUFFER_MAX_KB_SIZE = 1004;

    public const SQLSRV_ATTR_FETCHES_NUMERIC_TYPE = 1005;

    public const SQLSRV_ATTR_FETCHES_DATETIME_TYPE = 1006;

    public const SQLSRV_ATTR_FORMAT_DECIMALS = 1007;

    public const SQLSRV_ATTR_DECIMAL_PLACES = 1008;

    public const SQLSRV_ATTR_DATA_CLASSIFICATION = 1009;

    public const SQLSRV_PARAM_OUT_DEFAULT_SIZE = -1;

    public const SQLSRV_CURSOR_KEYSET = 1;

    public const SQLSRV_CURSOR_DYNAMIC = 2;

    public const SQLSRV_CURSOR_STATIC = 3;

    public const SQLSRV_CURSOR_BUFFERED = 42;

    /**
     * @since 7.4
     */
    public const SQLITE_ATTR_READONLY_STATEMENT = 1001;

    /**
     * @since 7.4
     */
    public const SQLITE_ATTR_EXTENDED_RESULT_CODES = 1002;

    /**
     * Provides a way to specify the action on the database session.
     * @since 7.2
     * @since 7.3
     */
    public const OCI_ATTR_ACTION = 1000;

    /**
     * Provides a way to specify the client info on the database session.
     * @since 7.2
     * @since 7.3
     */
    public const OCI_ATTR_CLIENT_INFO = 1001;

    /**
     * Provides a way to specify the client identifier on the database session.
     * @since 7.2
     * @since 7.3
     */
    public const OCI_ATTR_CLIENT_IDENTIFIER = 1002;

    /**
     * Provides a way to specify the module on the database session.
     * @since 7.2
     * @since 7.3
     */
    public const OCI_ATTR_MODULE = 1003;

    /**
     * The number of milliseconds to wait for individual round trips to the database to complete before timing out.
     * @since 8.0
     */
    public const OCI_ATTR_CALL_TIMEOUT = 1004;

    /**
     * Sets the date format.
     */
    public const FB_ATTR_DATE_FORMAT = 1000;

    /**
     * Sets the time format.
     */
    public const FB_ATTR_TIME_FORMAT = 1001;

    /**
     * Sets the timestamp format.
     */
    public const FB_ATTR_TIMESTAMP_FORMAT = 1002;

    /**
     * Sets the connection timeout in seconds.
     * @since 7.0
     */
    public const DBLIB_ATTR_CONNECTION_TIMEOUT = 1000;

    /**
     * Sets the query timeout in seconds.
     * @since 7.0
     */
    public const DBLIB_ATTR_QUERY_TIMEOUT = 1001;

    /**
     * Returns uniqueidentifier values as strings.
     * @since 7.0
     */
    public const DBLIB_ATTR_STRINGIFY_UNIQUEIDENTIFIER = 1002;

    /**
     * Returns the version of the underlying DB-Library.
     * @since 7.2
     */
    public const DBLIB_ATTR_VERSION = 1003;

    /**
     * Returns the TDS version used by the connection.
     * @since 7.3
     */
    public const DBLIB_ATTR_TDS_VERSION = 1004;

    /**
     * Skips empty result sets returned by stored procedures.
     * @since 7.3
     */
    public const DBLIB_ATTR_SKIP_EMPTY_ROWSETS = 1005;

    /**
     * Controls datetime conversion to strings.
     * @since 7.3
     */
    public const DBLIB_ATTR_DATETIME_CONVERT = 1006;

    /**
     * Selects the ODBC cursor library to use.
     */
    public const ODBC_ATTR_USE_CURSOR_LIBRARY = 1000;

    /**
     * Assume that data in the database is stored in UTF-8.
     */
    public const ODBC_ATTR_ASSUME_UTF8 = 1001;

    /**
     * Use the driver's cursor library if needed.
     */
    public const ODBC_SQL_USE_IF_NEEDED = 0;

    /**
     * Use the ODBC cursor library.
     */
    public const ODBC_SQL_USE_ODBC = 1;

    /**
     * Use the driver's native cursor library.
     */
    public const ODBC_SQL_USE_DRIVER = 2;

    /**
     * Creates a PDO instance representing a connection to a database
     * @param string $dsn The Data Source Name, or DSN, contains the information required to connect to the database. In general, a DSN consists of the PDO driver name, followed by a colon, followed by the PDO driver-specific connection syntax. Further information is available from the PDO driver-specific ...
     * @param string $username [optional]
     * @param string $password [optional]
     * @param array $options [optional]
     * @throws PDOException if the attempt to connect to the requested database fails.
     */
    public function __construct(
            string $dsn,
            string|null $username = null,
            string|null $password = null,
            array|null $options = null
        ) {}

    /**
     * Prepares a statement for execution and returns a statement object
     * @param string $query This must be a valid SQL statement for the target database server.
     * @param array $options [optional] This array holds one or more key=>value pairs to set attribute values for the PDOStatement object that this method returns. You would most commonly use this to set the PDO::ATTR_CURSOR value to PDO::CURSOR_SCROLL to request a scrollable cursor. Some drivers have ...
     * @return PDOStatement|false If the database server successfully prepares the statement, PDO::prepare returns a PDOStatement object. If the database server cannot successfully prepare the statement, PDO::prepare returns FALSE or emits PDOException (depending on error handling).
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true. Emulated prepared statements does not communicate with the database server so PDO::prepare does not check the statement.
     */
    public function prepare(
            string $query,
            array $options = []
        ): PDOStatement|false {}

    /**
     * Initiates a transaction
     *
     * Turns off autocommit mode. While autocommit mode is turned off,
     * changes made to the database via the PDO object instance are not committed
     * until you end the transaction by calling Calling {@link PDO::rollBack() will roll back all changes to the database and
     * return the connection to autocommit mode.
     *
     * Some databases, including MySQL, automatically issue an implicit COMMIT
     * when a database definition language (DDL) statement
     * such as DROP TABLE or CREATE TABLE is issued within a transaction.
     * The implicit COMMIT will prevent you from rolling back any other changes
     * within the transaction boundary.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException If there is already a transaction started or the driver does not support transactions Note: An exception is raised even when the PDO::ATTR_ERRMODE attribute is not PDO::ERRMODE_EXCEPTION.
     */
    public function beginTransaction(): bool {}

    /**
     * Commits a transaction
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException if there is no active transaction.
     */
    public function commit(): bool {}

    /**
     * Rolls back a transaction
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException if there is no active transaction.
     */
    public function rollBack(): bool {}

    /**
     * Checks if inside a transaction
     * @return bool TRUE if a transaction is currently active, and FALSE if not.
     */
    public function inTransaction(): bool {}

    /**
     * Set an attribute
     * @param int $attribute The attribute to modify.
     * @param mixed $value The value to set the attribute, might require a specific type depending on the attribute.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function setAttribute(
            int $attribute,
            mixed $value
        ): bool {}

    /**
     * Execute an SQL statement and return the number of affected rows
     * @param string $statement The SQL statement to prepare and execute. Data inside the query should be properly escaped.
     * @return int|false PDO::exec returns the number of rows that were modified or deleted by the SQL statement you issued. If no rows were affected, PDO::exec returns 0. This function may return Boolean FALSE, but may also return a non-Boolean value which evaluates to FALSE. Please read the section on ...
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function exec(string $statement): int|false {}

    /**
     * Executes an SQL statement, returning a result set as a PDOStatement object
     * @param string $query The SQL statement to prepare and execute. Data inside the query should be properly escaped.
     * @param int|null $fetchMode The fetch mode must be one of the PDO::FETCH_* constants.
     * @param mixed ...$fetch_mode_args Arguments of custom class constructor when the mode parameter is set to PDO::FETCH_CLASS.
     * @return PDOStatement|false PDO::query returns a PDOStatement object, or FALSE on failure or emits PDOException (depending on error handling).
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     * @see PDOStatement::setFetchMode For a full description of the second and following parameters.
     */
    public function query(
            string $query,
            int|null $fetchMode = null,
            mixed ...$fetchModeArgs
        ): PDOStatement|false {}

    /**
     * Returns the ID of the last inserted row or sequence value
     * @param string $name [optional] Name of the sequence object from which the ID should be returned.
     * @return string|false If a sequence name was not specified for the name parameter, PDO::lastInsertId returns a string representing the row ID of the last row that was inserted into the database. If a sequence name was specified for the name parameter, PDO::lastInsertId returns a string representing ...
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function lastInsertId(string|null $name = null): string|false {}

    /**
     * Fetch the SQLSTATE associated with the last operation on the database handle
     * @return mixed an SQLSTATE, a five characters alphanumeric identifier defined in the ANSI SQL-92 standard. Briefly, an SQLSTATE consists of a two characters class value followed by a three characters subclass value. A class value of 01 indicates a warning and is accompanied by a return code of ...
     */
    public function errorCode(): ?string {}

    /**
     * Fetch extended error information associated with the last operation on the database handle
     * @return array PDO::errorInfo returns an array of error information about the last operation performed by this database handle. The array consists of the following fields: Element Information 0 SQLSTATE error code (a five characters alphanumeric identifier defined in the ANSI SQL standard). 1 ...
     */
    public function errorInfo(): array {}

    /**
     * Retrieve a database connection attribute
     * @param int $attribute One of the PDO::ATTR_* constants. The constants that apply to database connections are as follows: PDO::ATTR_AUTOCOMMIT PDO::ATTR_CASE PDO::ATTR_CLIENT_VERSION PDO::ATTR_CONNECTION_STATUS PDO::ATTR_DRIVER_NAME PDO::ATTR_ERRMODE PDO::ATTR_ORACLE_NULLS PDO::ATTR_PERSISTENT ...
     * @return mixed A successful call returns the value of the requested PDO attribute. An unsuccessful call returns null.
     * @throws PDOException when the underlying driver does not support the requested attribute.
     */
    public function getAttribute(int $attribute): mixed {}

    /**
     * Quotes a string for use in a query.
     * @param string $string The string to be quoted.
     * @param int $type [optional] Provides a data type hint for drivers that have alternate quoting styles.
     * @return string|false a quoted string that is theoretically safe to pass into an SQL statement. Returns FALSE if the driver does not support quoting in this way.
     */
    public function quote(
            string $string,
            int $type = PDO::PARAM_STR
        ): string|false {}

    final public function __wakeup() {}

    final public function __sleep() {}

    /**
     * Return an array of available PDO drivers
     * @return array PDO::getAvailableDrivers returns an array of PDO driver names. If no drivers are available, it returns an empty array.
     */
    public static function getAvailableDrivers(): array {}

    /**
     * Registers an aggregating User Defined Function for use in SQL statements
     * @param string $function_name The name of the function used in SQL statements.
     * @param callable $step_func Callback function called for each row of the result set. Your PHP function should accumulate the result and store it in the aggregation context.
     * @param callable $finalize_func Callback function to aggregate the "stepped" data from each row. Once all the rows have been processed, this function will be called and it should then take the data from the aggregation context and return the result. This callback function should return a type ...
     * @param int $num_args [optional] Hint to the SQLite parser if the callback function accepts a predetermined number of arguments.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function sqliteCreateAggregate($function_name, $step_func, $finalize_func, $num_args = -1) {}

    /**
     * Registers a User Defined Function for use as a collating function in SQL statements
     * @param string $name Name of the SQL collating function to be created or redefined.
     * @param callable $callback The name of a PHP function or user-defined function to apply as a callback, defining the behavior of the collation. It should accept two strings and return as strcmp() does, i.e. it should return -1, 1, or 0 if the first string sorts before, sorts after, or is equal to the ...
     * @return bool TRUE on success or FALSE on failure.
     */
    public function sqliteCreateCollation($name, $callback) {}

    /**
     * Registers a User Defined Function for use in SQL statements
     * @param string $function_name The name of the function used in SQL statements.
     * @param callable $callback Callback function to handle the defined SQL function.
     * @param int $num_args [optional] The number of arguments that the SQL function takes. If this parameter is -1, then the SQL function may take any number of arguments.
     * @param int $flags [optional] A bitwise conjunction of flags. Currently, only PDO::SQLITE_DETERMINISTIC is supported, which specifies that the function always returns the same result given the same inputs within a single SQL statement.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function sqliteCreateFunction($function_name, $callback, $num_args = -1, $flags = 0) {}

    /**
     * Copy data from PHP array into table
     * @param string $tableName String containing table name
     * @param array $rows Array of strings with fields separated by separator
     * @param string $separator Separator used in rows array
     * @param string $nullAs How to interpret null values
     * @param string|null $fields List of fields to insert
     * @return bool TRUE on success or FALSE on failure.
     */
    public function pgsqlCopyFromArray($tableName, array $rows, $separator = "\t", $nullAs = "\\\\N", $fields = null) {}

    /**
     * Copy data from file into table
     * @param string $tableName String containing table name
     * @param string $filename Filename containing data to import
     * @param string $separator Separator used in file specified by filename
     * @param string $nullAs How to interpret null values
     * @param string|null $fields List of fields to insert
     * @return bool TRUE on success or FALSE on failure.
     */
    public function pgsqlCopyFromFile($tableName, $filename, $separator = "\t", $nullAs = "\\\\N", $fields = null) {}

    /**
     * Copy data from database table into PHP array
     * @param string $tableName String containing table name
     * @param string $separator Separator used in rows
     * @param string $nullAs How to interpret null values
     * @param string|null $fields List of fields to insert
     * @return array|false returns an array of rows, or FALSE on failure.
     */
    public function pgsqlCopyToArray($tableName, $separator = "\t", $nullAs = "\\\\N", $fields = null) {}

    /**
     * Copy data from table into file
     * @param string $tableName String containing table name
     * @param string $filename Filename to export data
     * @param string $separator Separator used in file specified by filename
     * @param string $nullAs How to interpret null values
     * @param string|null $fields List of fields to insert
     * @return bool TRUE on success or FALSE on failure.
     */
    public function pgsqlCopyToFile($tableName, $filename, $separator = "\t", $nullAs = "\\\\N", $fields = null) {}

    /**
     * Creates a new large object
     * @return string|false returns the OID of the newly created large object on success, or FALSE on failure.
     */
    public function pgsqlLOBCreate() {}

    /**
     * Opens an existing large object stream
     * @param string $oid A large object identifier.
     * @param string $mode If mode is r, open the stream for reading. If mode is w, open the stream for writing.
     * @return resource|false returns a stream resource on success or FALSE on failure.
     */
    public function pgsqlLOBOpen($oid, $mode = "rb") {}

    /**
     * Deletes the large object
     * @param string $oid A large object identifier.
     * @return bool TRUE on success or FALSE on failure.
     */
    public function pgsqlLOBUnlink($oid) {}

    /**
     * Get asynchronous notification
     * @param int $fetchMode The format the result set should be returned as, represented as a PDO::FETCH_* constant.
     * @param int $timeoutMilliseconds The length of time to wait for a response, in milliseconds.
     * @return array|false if one or more notifications is pending, returns a single row, with fields message and pid, otherwise FALSE.
     */
    public function pgsqlGetNotify($fetchMode = PDO::FETCH_DEFAULT, $timeoutMilliseconds = 0) {}

    /**
     * Get the server PID
     * @return int The server's PID.
     */
    public function pgsqlGetPid() {}

    /**
     * Connect to a database and return a PDO subclass for drivers that support it
     *
     * Creates an instance of a PDO subclass for the database being connected to, if it exists,
     * otherwise returns a generic PDO instance.
     * @throws PDOException if the attempt to connect to the requested database fails, regardless of which PDO::ATTR_ERRMODE is currently set.
     * @since 8.4
     */
    public static function connect(string $dsn, ?string $username = null, ?string $password = null, ?array $options = null): static {}
}
