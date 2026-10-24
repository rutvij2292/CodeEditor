<?php

/**
 * Represents a connection between PHP and a MySQL database.
 */
class mysqli
{
    /**
     * @var int
     */
    public string|int $affected_rows;

    /**
     * @var string
     */
    public string $client_info;

    /**
     * @var int
     */
    public int $client_version;

    /**
     * @var int
     */
    public int $connect_errno;

    /**
     * @var string
     */
    public string|null $connect_error;

    /**
     * @var int
     */
    public int $errno;

    /**
     * @var string
     */
    public string $error;

    /**
     * @var int
     */
    public int $field_count;

    /**
     * @var string
     */
    public string $host_info;

    /**
     * @var string
     */
    public string|null $info;

    /**
     * @var int|string
     */
    public int|string $insert_id;

    /**
     * @var string
     */
    public string $server_info;

    /**
     * @var int
     */
    public int $server_version;

    /**
     * @var string
     */
    public string $sqlstate;

    /**
     * @var int
     */
    public int $protocol_version;

    /**
     * @var int
     */
    public int $thread_id;

    /**
     * @var int
     */
    public int $warning_count;

    /**
     * @var array A list of errors, each as an associative array containing the errno, error, and sqlstate.
     */
    public array $error_list;

    public $stat;

    /**
     * Open a new connection to the MySQL server
     * @param string $hostname [optional] Can be either a host name or an IP address. Passing the NULL value or the string "localhost" to this parameter, the local host is assumed. When possible, pipes will be used instead of the TCP/IP protocol. Prepending host by p: opens a persistent connection. ...
     * @param string $username [optional] The MySQL user name. Defaults to ini_get("mysqli.default_user")
     * @param string $password [optional] If not provided or NULL, the MySQL server will attempt to authenticate the user against those user records which have no password only. This allows one username to be used with different permissions (depending on if a password as provided or not). Defaults to ...
     * @param string $database [optional] If provided will specify the default database to be used when performing queries. Defaults to ""
     * @param int $port [optional] Specifies the port number to attempt to connect to the MySQL server. Defaults to ini_get("mysqli.default_port")
     * @param string $socket [optional] Specifies the socket or named pipe that should be used. Defaults to ini_get("mysqli.default_socket")
     */
    public function __construct(
        string|null $hostname = null,
        string|null $username = null,
        string|null $password = null,
        string|null $database = null,
        int|null $port = null,
        string|null $socket = null
    ) {}

    /**
     * Turns on or off auto-committing database modifications
     * @param bool $enable Whether to turn on auto-commit or not.
     * @return bool true on success or false on failure.
     */
    public function autocommit(bool $enable): bool {}

    /**
     * Starts a transaction
     * @param int $flags [optional]
     * @param string $name [optional]
     * @return bool true on success or false on failure.
     * @since 5.5
     */
    public function begin_transaction(
        int $flags = 0,
        string|null $name = null
    ): bool {}

    /**
     * Changes the user of the specified database connection
     * @param string $username The MySQL user name.
     * @param string $password The MySQL password.
     * @param string|null $database The database to change to. If desired, the null value may be passed resulting in only changing the user and not selecting a database. To select a database in this case use the mysqli_select_db function.
     * @return bool true on success or false on failure.
     */
    public function change_user(
        string $username,
        string $password,
        string|null $database
    ): bool {}

    /**
     * Returns the current character set of the database connection
     * @return string The current character set of the connection
     */
    public function character_set_name(): string {}

    /**
     * @removed 5.4
     * @deprecated
     */
    public function client_encoding() {}

    /**
     * Closes a previously opened database connection
     * @return bool true on success or false on failure.
     */
    public function close(): bool {}

    /**
     * Commits the current transaction
     * @param int $flags A bitmask of MYSQLI_TRANS_COR_* constants.
     * @param string|null $name If provided then COMMIT $name is executed.
     * @return bool true on success or false on failure.
     */
    public function commit(
        int $flags = 0,
        string|null $name = null
    ): bool {}

    /**
     * Open a new connection to the MySQL server
     *
     * Opens a connection to the MySQL Server.
     * @param string|null $hostname [optional]
     * @param string|null $username [optional]
     * @param string|null $password [optional]
     * @param string|null $database [optional]
     * @param int|null $port [optional]
     * @param string|null $socket [optional]
     * @return bool mysqli::__construct always returns an object which represents the connection to a MySQL Server, regardless of it being successful or not. mysqli_connect returns an object which represents the connection to a MySQL Server, or false on failure. mysqli::connect returns true on success or ...
     */
    public function connect(
        string|null $hostname = null,
        string|null $username = null,
        string|null $password = null,
        string|null $database = null,
        int|null $port = null,
        string|null $socket = null
    ): bool {}

    /**
     * Dump debugging information into the log
     * @return bool true on success or false on failure.
     */
    public function dump_debug_info(): bool {}

    /**
     * Performs debugging operations
     * @param string $options A string representing the debugging operation to perform
     * @return bool true.
     */
    public function debug(string $options): bool {}

    /**
     * Returns a character set object
     * @return object|null The function returns a character set object with the following properties: charset Character set name collation Collation name dir Directory the charset description was fetched from (?) or "" for built-in character sets min_length Minimum character length in bytes max_length ...
     */
    public function get_charset(): ?object {}

    /**
     * Prepares the SQL query, binds parameters, and executes it. The
     * mysqli::execute_query() method is a shortcut for mysqli::prepare(),
     * mysqli_stmt::bind_param(), mysqli_stmt::execute(), and
     * mysqli_stmt::get_result().
     * The statement template can contain zero or more question mark (?)
     * parameter markers⁠—also called placeholders. The parameter values must be
     * provided as an array using params parameter.
     * A prepared statement is created under the hood but it's never exposed
     * outside of the function. It's impossible to access properties of the
     * statement as one would do with the mysqli_stmt object. Due to this
     * limitation, the status information is copied to the mysqli object and is
     * available using its ...
     * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions. Note: The markers are legal only in certain places in SQL statements. For ...
     * @param array|null $params An optional list array with as many elements as there are bound parameters in the SQL statement being executed. Each value is treated as a string.
     * @return mysqli_result|bool Returns false on failure. For successful queries which produce a result set, such as SELECT, SHOW, DESCRIBE or EXPLAIN, returns a mysqli_result object. For other successful queries, returns true.
     * @since 8.2
     */
    public function execute_query(string $query, ?array $params = null): mysqli_result|bool {}

    /**
     * Returns the MySQL client version as a string
     * @return string A string that represents the MySQL client library version
     * @deprecated 8.1
     */
    public function get_client_info(): string {}

    /**
     * Returns statistics about the client connection
     * @return array an array with connection stats.
     */
    public function get_connection_stats(): array {}

    /**
     * Returns the version of the MySQL server
     * @return string A character string representing the server version.
     */
    public function get_server_info(): string {}

    /**
     * Get result of SHOW WARNINGS
     * @return mysqli_warning|false Returns a singly linked list comprised of mysqli_warning or false if there are no warnings.
     */
    public function get_warnings(): mysqli_warning|false {}

    /**
     * Initializes MySQLi object
     * @return bool|null mysqli::init returns null on success, or false on failure. mysqli_init returns an object on success, or false on failure.
     * @deprecated 8.1
     */
    public function init() {}

    /**
     * Asks the server to kill a MySQL thread
     * @param int $process_id
     * @return bool true on success or false on failure.
     */
    public function kill(int $process_id): bool {}

    /**
     * Performs one or more queries on the database
     * @param string $query A string containing the queries to be executed. Multiple queries must be separated by a semicolon. If the query contains any variable input then parameterized prepared statements should be used instead. Alternatively, the data must be properly formatted and all strings must be ...
     * @return bool false if the first statement failed. To retrieve subsequent errors from other statements you have to call mysqli_next_result first.
     */
    public function multi_query(string $query): bool {}

    /**
     * @param string $host [optional]
     * @param string $username [optional]
     * @param string $password [optional]
     * @param string $database [optional]
     * @param int $port [optional]
     * @param string $socket [optional]
     * @removed 8.0
     */
    public function mysqli($host = null, $username = null, $password = null, $database = null, $port = null, $socket = null) {}

    /**
     * Check if there are any more query results from a multi query
     * @return bool true on success or false on failure.
     */
    public function more_results(): bool {}

    /**
     * Prepare next result from multi_query
     * @return bool true on success or false on failure.
     */
    public function next_result(): bool {}

    /**
     * Set options
     * @param int $option The option that you want to set. It can be one of the following values: Valid options Name Description MYSQLI_OPT_CONNECT_TIMEOUT connection timeout in seconds (supported on Windows with TCP/IP since PHP 5.3.1) MYSQLI_OPT_LOCAL_INFILE enable/disable use of LOAD LOCAL INFILE ...
     * @param string|int $value The value for the option.
     * @return bool true on success or false on failure.
     */
    public function options(int $option, $value): bool {}

    /**
     * Pings a server connection, or tries to reconnect if the connection has gone down
     * @return bool true on success or false on failure.
     */
    public function ping(): bool {}

    /**
     * Prepares an SQL statement for execution
     * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions. The markers are legal only in certain places in SQL statements. For example, ...
     * @return mysqli_stmt|false mysqli_prepare returns a statement object or false if an error occurred.
     */
    public function prepare(string $query): mysqli_stmt|false {}

    /**
     * Performs a query on the database
     * @param string $query The query string. If the query contains any variable input then parameterized prepared statements should be used instead. Alternatively, the data must be properly formatted and all strings must be escaped using the mysqli_real_escape_string function.
     * @param int $result_mode [optional] The result mode can be one of 3 constants indicating how the result will be returned from the MySQL server. MYSQLI_STORE_RESULT (default) - returns a mysqli_result object with buffered result set. MYSQLI_USE_RESULT - returns a mysqli_result object with unbuffered ...
     * @return mysqli_result|bool Returns false on failure. For successful queries which produce a result set, such as SELECT, SHOW, DESCRIBE or EXPLAIN, mysqli_query will return a mysqli_result object. For other successful queries mysqli_query will return true.
     */
    public function query(
        string $query,
        int $result_mode = MYSQLI_STORE_RESULT
    ): mysqli_result|bool {}

    /**
     * Opens a connection to a mysql server
     * @param string $hostname [optional] Can be either a host name or an IP address. Passing the null value or the string "localhost" to this parameter, the local host is assumed. When possible, pipes will be used instead of the TCP/IP protocol.
     * @param string $username [optional] The MySQL user name.
     * @param string $password [optional] If provided or null, the MySQL server will attempt to authenticate the user against those user records which have no password only. This allows one username to be used with different permissions (depending on if a password as provided or not).
     * @param string $database [optional] If provided will specify the default database to be used when performing queries.
     * @param int $port [optional] Specifies the port number to attempt to connect to the MySQL server.
     * @param string $socket [optional] Specifies the socket or named pipe that should be used. Specifying the socket parameter will not explicitly determine the type of connection to be used when connecting to the MySQL server. How the connection is made to the MySQL database is determined by the host ...
     * @param int $flags [optional] With the parameter flags you can set different connection options: Supported flags Name Description MYSQLI_CLIENT_COMPRESS Use compression protocol MYSQLI_CLIENT_FOUND_ROWS return number of matched rows, not the number of affected rows MYSQLI_CLIENT_IGNORE_SPACE Allow ...
     * @return bool true on success or false on failure.
     */
    public function real_connect(
        string|null $hostname = null,
        string|null $username = null,
        string|null $password = null,
        string|null $database = null,
        int|null $port = null,
        string|null $socket = null,
        int $flags = 0
    ): bool {}

    /**
     * Escapes special characters in a string for use in an SQL statement, taking into account the current charset of the connection
     * @param string $string The string to be escaped. Characters encoded are NUL (ASCII 0), \n, \r, \, ', ", and Control-Z.
     * @return string an escaped string.
     */
    public function real_escape_string(string $string): string {}

    /**
     * Poll connections
     * @param array &$read
     * @param array &$error
     * @param array &$reject
     * @param int $seconds Number of seconds to wait, must be non-negative.
     * @param int $microseconds [optional] Number of microseconds to wait, must be non-negative.
     * @return int|false number of ready connections in success, false otherwise.
     */
    public static function poll(
        array|null &$read,
        array|null &$error,
        array &$reject,
        int $seconds,
        int $microseconds = 0
    ): int|false {}

    /**
     * Get result from async query
     * @return mysqli_result|bool false on failure, mysqli_result for queries which produce a result set, true otherwise
     */
    public function reap_async_query(): mysqli_result|bool {}

    /**
     * Escapes special characters in a string for use in an SQL statement, taking into account the current charset of the connection
     * @param string $string The string to be escaped. Characters encoded are NUL (ASCII 0), \n, \r, \, ', ", and Control-Z.
     * @return string
     */
    public function escape_string(string $string): string {}

    /**
     * Execute an SQL query
     * @param string $query The query, as a string. If the query contains any variable input then parameterized prepared statements should be used instead. Alternatively, the data must be properly formatted and all strings must be escaped using the mysqli_real_escape_string function.
     * @return bool true on success or false on failure.
     */
    public function real_query(string $query): bool {}

    /**
     * Removes the named savepoint from the set of savepoints of the current transaction
     * @param string $name The identifier of the savepoint.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 5.5
     */
    public function release_savepoint(string $name): bool {}

    /**
     * Rolls back current transaction
     * @param int $flags [optional] A bitmask of MYSQLI_TRANS_COR_* constants.
     * @param string $name [optional] If provided then ROLLBACK $name is executed.
     * @return bool true on success or false on failure.
     * @since 5.5 Added flags and name parameters.
     */
    public function rollback(
        int $flags = 0,
        string|null $name = null
    ): bool {}

    /**
     * Set a named transaction savepoint
     * @param string $name The identifier of the savepoint.
     * @return bool Returns TRUE on success or FALSE on failure.
     * @since 5.5
     */
    public function savepoint(string $name): bool {}

    /**
     * Selects the default database for database queries
     * @param string $database The database name.
     * @return bool true on success or false on failure.
     */
    public function select_db(string $database): bool {}

    /**
     * Sets the client character set
     * @param string $charset The desired character set.
     * @return bool true on success or false on failure
     */
    public function set_charset(string $charset): bool {}

    /**
     * @param int $option
     * @param string|int $value
     */
    public function set_opt(int $option, $value): bool {}

    /**
     * Used for establishing secure connections using SSL
     * @param string|null $key The path name to the key file.
     * @param string|null $certificate The path name to the certificate file.
     * @param string|null $ca_certificate The path name to the certificate authority file.
     * @param string|null $ca_path The pathname to a directory that contains trusted SSL CA certificates in PEM format.
     * @param string|null $cipher_algos A list of allowable ciphers to use for SSL encryption.
     * @return bool This function always returns TRUE value.
     */
    public function ssl_set(
        string|null $key,
        string|null $certificate,
        string|null $ca_certificate,
        string|null $ca_path,
        string|null $cipher_algos
    ): bool {}

    /**
     * Gets the current system status
     * @return string|false A string describing the server status. false if an error occurred.
     */
    public function stat(): string|false {}

    /**
     * Initializes a statement and returns an object for use with mysqli_stmt_prepare
     * @return mysqli_stmt an object.
     */
    public function stmt_init(): mysqli_stmt|false {}

    /**
     * Transfers a result set from the last query
     * @param int $mode [optional] The option that you want to set
     * @return mysqli_result|false a buffered result object or false if an error occurred. mysqli_store_result returns false in case the query didn't return a result set (if the query was, for example an INSERT statement). This function also returns false if the reading of the result set failed. You can ...
     */
    public function store_result(
        $mode = 0
    ): mysqli_result|false {}

    /**
     * Returns whether thread safety is given or not
     * @return bool true if the client library is thread-safe, otherwise false.
     */
    public function thread_safe(): bool {}

    /**
     * Initiate a result set retrieval
     * @return mysqli_result|false an unbuffered result object or false if an error occurred.
     */
    public function use_result(): mysqli_result|false {}

    /**
     * Refreshes
     *
     * Flushes tables or caches, or resets the replication server information.
     * @param int $flags MYSQLI_REFRESH_*
     * @return bool TRUE if the refresh was a success, otherwise FALSE
     * @since 5.3
     */
    public function refresh(int $flags): bool {}

    /**
     * @param string $string
     * @return string
     * @since 8.6
     */
    public function quote_string(string $string): string {}
}
