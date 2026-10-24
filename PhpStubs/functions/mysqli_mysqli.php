<?php

/**
 * Gets the number of affected rows in a previous MySQL operation
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string|int An integer greater than zero indicates the number of rows affected or retrieved. Zero indicates that no records were updated for an UPDATE statement, no rows matched the WHERE clause in the query or that no query has yet been executed. -1 indicates that the query returned an ...
 */
function mysqli_affected_rows(mysqli $mysql): string|int {}

/**
 * Turns on or off auto-committing database modifications
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param bool $enable Whether to turn on auto-commit or not.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_autocommit(mysqli $mysql, bool $enable): bool {}

/**
 * Starts a transaction
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $flags [optional]
 * @param string|null $name [optional]
 * @return bool true on success or false on failure.
 * @since 5.5
 */
function mysqli_begin_transaction(mysqli $mysql, int $flags = 0, ?string $name = null): bool {}

/**
 * Changes the user of the specified database connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $username The MySQL user name.
 * @param string $password The MySQL password.
 * @param string|null $database The database to change to. If desired, the NULL value may be passed resulting in only changing the user and not selecting a database.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_change_user(mysqli $mysql, string $username, string $password, ?string $database): bool {}

/**
 * Returns the current character set of the database connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string The current character set of the connection
 */
function mysqli_character_set_name(mysqli $mysql): string {}

/**
 * Closes a previously opened database connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return bool Always returns true.
 */
function mysqli_close(mysqli $mysql): true {}

/**
 * Commits the current transaction
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $flags [optional] A bitmask of MYSQLI_TRANS_COR_* constants
 * @param string|null $name [optional] If provided then COMMITname is executed
 * @return bool Returns true on success or false on failure.
 */
function mysqli_commit(mysqli $mysql, int $flags = 0, ?string $name = null): bool {}

/**
 * Open a new connection to the MySQL server
 * Alias of mysqli::__construct
 * @param string|null $hostname Can be either a host name or an IP address. Passing the NULL value or the string "localhost" to this parameter, the local host is assumed. When possible, pipes will be used instead of the TCP/IP protocol.
 * @param string|null $username The MySQL user name.
 * @param string|null $password If not provided or NULL, the MySQL server will attempt to authenticate the user against those user records which have no password only.
 * @param string|null $database If provided will specify the default database to be used when performing queries.
 * @param int|null $port Specifies the port number to attempt to connect to the MySQL server.
 * @param string|null $socket Specifies the socket or named pipe that should be used.
 * @return mysqli|false object which represents the connection to a MySQL Server or false if an error occurred.
 */
function mysqli_connect(?string $hostname = null, ?string $username = null, ?string $password = null, ?string $database = null, ?int $port = null, ?string $socket = null): mysqli|false {}

/**
 * Returns the error code from last connect call
 * @return int Last error code number from the last call to mysqli_connect(). Zero means no error occurred.
 */
function mysqli_connect_errno(): int {}

/**
 * Returns a string description of the last connect error
 * @return string|null Last error message string from the last call to mysqli_connect().
 */
function mysqli_connect_error(): ?string {}

/**
 * Adjusts the result pointer to an arbitrary row in the result
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $offset The row offset. Must be between zero and the total number of rows minus one (0..mysqli_num_rows - 1).
 * @return bool Returns TRUE on success or FALSE on failure.
 */
function mysqli_data_seek(mysqli_result $result, int $offset): bool {}

/**
 * Dump debugging information into the log
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return bool Returns true on success or false on failure.
 */
function mysqli_dump_debug_info(mysqli $mysql): bool {}

/**
 * Performs debugging operations using the Fred Fish debugging library.
 * @param string $options A string representing the debugging operation to perform The debug control string is a sequence of colon separated fields as follows: <field_1>:<field_2>:<field_N> Each field consists of a mandatory flag character followed by an optional , and comma separated list of ...
 * @return bool Always returns true.
 */
function mysqli_debug(string $options): true {}

/**
 * Returns the error code for the most recent function call
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int An error code value for the last call, if it failed. zero means no error occurred.
 */
function mysqli_errno(mysqli $mysql): int {}

/**
 * Returns a list of errors from the last command executed
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return array A list of errors, each as an associative array containing the errno, error, and sqlstate.
 * @since 5.4
 */
function mysqli_error_list(mysqli $mysql): array {}

/**
 * Returns a list of errors from the last statement executed
 * @param mysqli_stmt $statement A statement identifier returned by mysqli_stmt_init().
 * @return array A list of errors, each as an associative array containing the errno, error, and sqlstate.
 * @since 5.4
 */
function mysqli_stmt_error_list(mysqli_stmt $statement): array {}

/**
 * Returns a string description of the last error
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string A string that describes the error. An empty string if no error occurred.
 */
function mysqli_error(mysqli $mysql): string {}

/**
 * Executes a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param array|null $params [optional] An optional list array with as many elements as there are bound parameters in the SQL statement being executed. Each value is treated as a string.
 * @return bool true on success or false on failure.
 */
function mysqli_stmt_execute(mysqli_stmt $statement, ?array $params = null): bool {}

/**
 * Executes a prepared statement
 * Alias for mysqli_stmt_execute
 * @param mysqli_stmt $statement
 * @param array|null $params [optional] An optional list array with as many elements as there are bound parameters in the SQL statement being executed. Each value is treated as a string.
 * @return bool
 */
function mysqli_execute(mysqli_stmt $statement, ?array $params = null): bool {}

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
 * @param mysqli $mysql A mysqli object returned by mysqli_connect() or mysqli_init()
 * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions. Note: The markers are legal only in certain places in SQL statements. For ...
 * @param ?array $params An optional list array with as many elements as there are bound parameters in the SQL statement being executed. Each value is treated as a string.
 * @return mysqli_result|bool Returns false on failure. For successful queries which produce a result set, such as SELECT, SHOW, DESCRIBE or EXPLAIN, returns a mysqli_result object. For other successful queries, returns true.
 * @since 8.2
 */
function mysqli_execute_query(mysqli $mysql, string $query, ?array $params = null): mysqli_result|bool {}

/**
 * Returns the next field in the result set
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return object|false Returns an object which contains field definition information or FALSE if no field information is available.
 */
function mysqli_fetch_field(mysqli_result $result): object|false {}

/**
 * Returns an array of objects representing the fields in a result set
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return array Returns an array of objects which contains field definition information.
 */
function mysqli_fetch_fields(mysqli_result $result): array {}

/**
 * Fetch meta-data for a single field
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $index The field number. This value must be in the range from 0 to number of fields - 1.
 * @return object|false Returns an object which contains field definition information or FALSE if no field information for specified fieldnr is available.
 */
function mysqli_fetch_field_direct(mysqli_result $result, int $index): object|false {}

/**
 * Returns the lengths of the columns of the current row in the result set
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return int[]|false An array of integers representing the size of each column (not including any terminating null characters). FALSE if an error occurred.
 */
function mysqli_fetch_lengths(mysqli_result $result): array|false {}

/**
 * Fetch all result rows as an associative array, a numeric array, or both
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $mode This optional parameter is a constant indicating what type of array should be produced from the current row data. The possible values for this parameter are the constants MYSQLI_ASSOC, MYSQLI_NUM, or MYSQLI_BOTH.
 * @return array Returns an array of associative or numeric arrays holding result rows.
 */
function mysqli_fetch_all(
    mysqli_result $result,
    int $mode = MYSQLI_NUM
): array {}

/**
 * Fetch the next row of a result set as an associative, a numeric array, or both
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $mode This optional parameter is a constant indicating what type of array should be produced from the current row data. The possible values for this parameter are the constants MYSQLI_ASSOC, MYSQLI_NUM, or MYSQLI_BOTH. By using the MYSQLI_ASSOC constant this function will behave ...
 * @return array|false|null an array representing the fetched row, null if there are no more rows in the result set, or false on failure.
 */
function mysqli_fetch_array(mysqli_result $result, int $mode = MYSQLI_BOTH): array|false|null {}

/**
 * Fetch the next row of a result set as an associative array
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return array|false|null an associative array representing the fetched row, where each key in the array represents the name of one of the result set's columns, null if there are no more rows in the result set, or false on failure.
 */
function mysqli_fetch_assoc(mysqli_result $result): array|null|false {}

/**
 * Fetch the next row of a result set as an object
 *
 * Fetches one row of data from the result set and returns it as an object, where each property
 * represents the name of the result set's column. Each subsequent call to this function will return
 * the next row within the result set, or null if there are no more rows.
 * @template T of object Fetch the next row of a result set as an object
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param class-string<T> $class [optional] The name of the class to instantiate, set the properties of and return. If not specified, a stdClass object is returned.
 * @param array $constructor_args [optional] An optional array of parameters to pass to the constructor for class_name objects.
 * @return T|stdClass|null|false an object representing the fetched row, where each property represents the name of the result set's column, null if there are no more rows in the result set, or false on failure.
 */
function mysqli_fetch_object(mysqli_result $result, string $class = 'stdClass', array $constructor_args = []): object|null|false {}

/**
 * Fetch the next row of a result set as an enumerated array
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return array|null|false an enumerated array representing the fetched row, null if there are no more rows in the result set, or false on failure.
 */
function mysqli_fetch_row(mysqli_result $result): array|false|null {}

/**
 * Fetch a single column from the next row of a result set
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $column [optional] 0-indexed number of the column you wish to retrieve from the row. If no value is supplied, the first column will be returned.
 * @return string|int|float|false|null a single column from the next row of a result set or false if there are no more rows.
 */
function mysqli_fetch_column(mysqli_result $result, int $column = 0): string|int|float|false|null {}

/**
 * Returns the number of columns for the most recent query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int An integer representing the number of fields in a result set.
 */
function mysqli_field_count(mysqli $mysql): int {}

/**
 * Set result pointer to a specified field offset
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @param int $index The field number. This value must be in the range from 0 to number of fields - 1.
 */
function mysqli_field_seek(mysqli_result $result, int $index): true {}

/**
 * Get current field offset of a result pointer
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return int Returns current offset of field cursor.
 */
function mysqli_field_tell(mysqli_result $result): int {}

/**
 * Frees the memory associated with a result
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return void No value is returned.
 */
function mysqli_free_result(mysqli_result $result): void {}

/**
 * Returns client Zval cache statistics
 * Available only with mysqlnd.
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return array|false an array with client Zval cache stats if success, false otherwise.
 * @removed 5.4
 */
function mysqli_get_cache_stats(mysqli $mysql) {}

/**
 * Returns statistics about the client connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return array an array with connection stats.
 */
function mysqli_get_connection_stats(mysqli $mysql): array {}

/**
 * Returns client per-process statistics
 * @return array an array with client stats.
 */
function mysqli_get_client_stats(): array {}

/**
 * Returns a character set object
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return object|null The function returns a character set object with the following properties: charset Character set name collation Collation name dir Directory the character set description was fetched from or "" for built-in character sets min_length Minimum character length in bytes max_length ...
 */
function mysqli_get_charset(mysqli $mysql): ?object {}

/**
 * Get MySQL client info
 * @param mysqli|null $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string|null A string that represents the MySQL client library version
 */
function mysqli_get_client_info(
    ?mysqli $mysql = null
): string {}

/**
 * Returns the MySQL client version as an integer
 * @return int A number that represents the MySQL client library version in format: main_version*10000 + minor_version *100 + sub_version. For example, 4.1.0 is returned as 40100. This is useful to quickly determine the version of the client library to know if some capability exists.
 */
function mysqli_get_client_version(): int {}

/**
 * Returns a string representing the type of connection used
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string A character string representing the server hostname and the connection type.
 */
function mysqli_get_host_info(mysqli $mysql): string {}

/**
 * Return information about open and cached links
 * @return array mysqli_get_links_stats() returns an associative array with three elements, keyed as follows: total An integer indicating the total number of open links in any state. active_plinks An integer representing the number of active persistent connections. cached_plinks An integer ...
 * @since 5.6
 */
function mysqli_get_links_stats(): array {}

/**
 * Returns the version of the MySQL protocol used
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int Returns an integer representing the protocol version
 */
function mysqli_get_proto_info(mysqli $mysql): int {}

/**
 * Returns the version of the MySQL server
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string A character string representing the server version.
 */
function mysqli_get_server_info(mysqli $mysql): string {}

/**
 * Returns the version of the MySQL server as an integer
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int An integer representing the server version. The form of this version number is main_version * 10000 + minor_version * 100 + sub_version (i.e. version 4.1.0 is 40100).
 */
function mysqli_get_server_version(mysqli $mysql): int {}

/**
 * Get result of SHOW WARNINGS
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return mysqli_warning|false Returns a singly linked list comprised of mysqli_warning or false if there are no warnings.
 */
function mysqli_get_warnings(mysqli $mysql): mysqli_warning|false {}

/**
 * Initializes MySQLi and returns a resource for use with mysqli_real_connect()
 * @return mysqli|false mysqli::init returns null on success, or false on failure. mysqli_init returns an object on success, or false on failure.
 * @see mysqli_real_connect()
 */
function mysqli_init(): mysqli|false {}

/**
 * Retrieves information about the most recently executed query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string|null A character string representing additional information about the most recently executed query.
 */
function mysqli_info(mysqli $mysql): ?string {}

/**
 * Returns the value generated for an AUTO_INCREMENT column by the last query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int|string The value of the AUTO_INCREMENT field that was updated by the previous query. Returns zero if there was no previous query on the connection or if the query did not update an AUTO_INCREMENT value. If the number is greater than the maximum int value, it will be returned as a string.
 */
function mysqli_insert_id(mysqli $mysql): string|int {}

/**
 * Asks the server to kill a MySQL thread
 * @see mysqli_thread_id()
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $process_id
 * @return bool Returns true on success or false on failure.
 */
function mysqli_kill(mysqli $mysql, int $process_id): bool {}

/**
 * Unsets user defined handler for load local infile command
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return void No value is returned.
 * @removed 5.5
 */
function mysqli_set_local_infile_default(mysqli $mysql) {}

/**
 * Set callback function for LOAD DATA LOCAL INFILE command
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param callable $read_func A callback function or object method taking the following parameters: A PHP stream associated with the SQL commands INFILE A string buffer to store the rewritten input into The maximum number of characters to be stored in the buffer If an error occurs you can store an ...
 * @return bool Returns TRUE on success or FALSE on failure.
 * @removed 5.5
 */
function mysqli_set_local_infile_handler(mysqli $mysql, callable $read_func): bool {}

/**
 * Check if there are any more query results from a multi query
 * @see mysqli_multi_query()
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return bool Returns true if one or more result sets (including errors) are available from a previous call to mysqli_multi_query, otherwise false.
 */
function mysqli_more_results(mysqli $mysql): bool {}

/**
 * Performs one or more queries on the database
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $query A string containing the queries to be executed. Multiple queries must be separated by a semicolon.
 * @return bool Returns FALSE if the first statement failed. To retrieve subsequent errors from other statements you have to call mysqli_next_result() first.
 */
function mysqli_multi_query(
    mysqli $mysql,
    string $query
): bool {}

/**
 * Prepare next result from multi_query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return bool Returns true on success or false on failure. Also returns false if the next statement resulted in an error, unlike mysqli_more_results.
 */
function mysqli_next_result(mysqli $mysql): bool {}

/**
 * Gets the number of fields in the result set
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return int An int representing the number of fields.
 */
function mysqli_num_fields(mysqli_result $result): int {}

/**
 * Gets the number of rows in a result
 * @param mysqli_result $result A mysqli_result object returned by mysqli_query(), mysqli_store_result(), mysqli_use_result() or mysqli_stmt_get_result().
 * @return string|int Returns number of rows in the result set.
 */
function mysqli_num_rows(mysqli_result $result): string|int {}

/**
 * Set options
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $option The option that you want to set. It can be one of the following values: Valid options Name Description MYSQLI_OPT_CONNECT_TIMEOUT Connection timeout in seconds MYSQLI_OPT_READ_TIMEOUT Command execution result timeout in seconds. Available as of PHP 7.2.0. MYSQLI_OPT_LOCAL_INFILE ...
 * @param string|int $value The value for the option.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_options(mysqli $mysql, int $option, $value): bool {}

/**
 * Pings a server connection, or tries to reconnect if the connection has gone down
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return bool Returns true on success or false on failure.
 */
function mysqli_ping(mysqli $mysql): bool {}

/**
 * Poll connections
 * @param array|null &$read List of connections to check for outstanding results that can be read.
 * @param array|null &$error List of connections on which an error occurred, for example, query failure or lost connection.
 * @param array &$reject List of connections rejected because no pending asynchronous query exists to poll.
 * @param int $seconds Maximum number of seconds to wait, must be non-negative.
 * @param int $microseconds [optional]
 * @return int|false number of ready connections upon success, FALSE otherwise.
 */
function mysqli_poll(?array &$read, ?array &$error, array &$reject, int $seconds, int $microseconds = 0): int|false {}

/**
 * Prepares an SQL statement for execution
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions.
 * @return mysqli_stmt|false A statement object or FALSE if an error occurred.
 */
function mysqli_prepare(mysqli $mysql, string $query): mysqli_stmt|false {}

/**
 * Enables or disables internal report functions
 * @param int $flags Supported flags Name Description MYSQLI_REPORT_OFF Turns reporting off MYSQLI_REPORT_ERROR Report errors from mysqli function calls MYSQLI_REPORT_STRICT Throw mysqli_sql_exception for errors instead of warnings MYSQLI_REPORT_INDEX Report if no index or bad index was used in a ...
 * @return bool Always returns true.
 */
function mysqli_report(int $flags): bool {}

/**
 * Performs a query on the database
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $query An SQL query
 * @param int $result_mode The result mode can be one of 3 constants indicating how the result will be returned from the MySQL server. MYSQLI_STORE_RESULT (default) - returns a mysqli_result object with buffered result set. MYSQLI_USE_RESULT - returns a mysqli_result object with unbuffered result set. ...
 * @return mysqli_result|bool For successful SELECT, SHOW, DESCRIBE or EXPLAIN queries, mysqli_query() will return a mysqli_result object. For other successful queries mysqli_query() will return TRUE. Returns FALSE on failure.
 */
function mysqli_query(
    mysqli $mysql,
    string $query,
    int $result_mode = MYSQLI_STORE_RESULT
): mysqli_result|bool {}

/**
 * Opens a connection to a mysql server
 * @see mysqli_connect()
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string|null $hostname [optional]
 * @param string|null $username [optional]
 * @param string|null $password [optional]
 * @param string|null $database [optional]
 * @param int|null $port [optional]
 * @param string|null $socket [optional]
 * @param int $flags With the parameter flags you can set different connection options: Supported flags Name Description MYSQLI_CLIENT_COMPRESS Use compression protocol MYSQLI_CLIENT_FOUND_ROWS Return the number of matched rows, not the number of affected rows MYSQLI_CLIENT_IGNORE_SPACE Allow spaces ...
 * @return bool Returns true on success or false on failure.
 */
function mysqli_real_connect(mysqli $mysql, ?string $hostname = null, ?string $username = null, ?string $password = null, ?string $database = null, ?int $port = null, ?string $socket = null, int $flags = 0): bool {}

/**
 * Escapes special characters in a string for use in an SQL statement, taking into account the current charset of the connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $string The string to be escaped. Characters encoded are NUL (ASCII 0), \n, \r, \, ', ", and Control-Z.
 * @return string Returns an escaped string.
 */
function mysqli_real_escape_string(mysqli $mysql, string $string): string {}

/**
 * Execute an SQL query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $query The query string.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_real_query(
    mysqli $mysql,
    string $query
): bool {}

/**
 * Get result from async query
 * Available only with mysqlnd.
 * @see mysqli_poll()
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return mysqli_result|bool false on failure, mysqli_result for queries which produce a result set, true otherwise
 */
function mysqli_reap_async_query(mysqli $mysql): mysqli_result|bool {}

/**
 * Removes the named savepoint from the set of savepoints of the current transaction
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $name The identifier of the savepoint.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function mysqli_release_savepoint(mysqli $mysql, string $name): bool {}

/**
 * Rolls back current transaction
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $flags [optional] A bitmask of MYSQLI_TRANS_COR_* constants
 * @param string|null $name [optional] If provided then ROLLBACKname is executed
 * @return bool Returns true on success or false on failure.
 */
function mysqli_rollback(mysqli $mysql, int $flags = 0, ?string $name = null): bool {}

/**
 * Set a named transaction savepoint
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $name The identifier of the savepoint.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function mysqli_savepoint(mysqli $mysql, string $name): bool {}

/**
 * Selects the default database for database queries
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $database The database name.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_select_db(mysqli $mysql, string $database): bool {}

/**
 * Sets the client character set
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $charset The desired character set.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_set_charset(mysqli $mysql, string $charset): bool {}

/**
 * Returns the total number of rows changed, deleted, inserted, or matched by the last statement executed
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return int|string If the number of affected rows is greater than maximum PHP int value, the number of affected rows will be returned as a string value.
 */
function mysqli_stmt_affected_rows(mysqli_stmt $statement): string|int {}

/**
 * Used to get the current value of a statement attribute
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param int $attribute The attribute that you want to get.
 * @return int|false Returns FALSE if the attribute is not found, otherwise returns the value of the attribute.
 */
function mysqli_stmt_attr_get(mysqli_stmt $statement, int $attribute): int {}

/**
 * Used to modify the behavior of a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param int $attribute The attribute that you want to set. It can have one of the following values: Attribute values Character Description MYSQLI_STMT_ATTR_UPDATE_MAX_LENGTH Setting to true causes mysqli_stmt_store_result to update the metadata MYSQL_FIELD->max_length value. ...
 * @param int $value The value to assign to the attribute.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_attr_set(mysqli_stmt $statement, int $attribute, int $value): bool {}

/**
 * Returns the number of fields in the given statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return int Returns an integer representing the number of columns.
 */
function mysqli_stmt_field_count(mysqli_stmt $statement): int {}

/**
 * Initializes a statement and returns an object for use with mysqli_stmt_prepare
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return mysqli_stmt|false Returns a mysqli_stmt object.
 */
function mysqli_stmt_init(mysqli $mysql): mysqli_stmt|false {}

/**
 * Prepares an SQL statement for execution
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions. The markers are legal only in certain places in SQL statements. For example, ...
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_prepare(mysqli_stmt $statement, string $query): bool {}

/**
 * Returns result set metadata from a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return mysqli_result|false Returns a result object or FALSE if an error occurred
 */
function mysqli_stmt_result_metadata(mysqli_stmt $statement): mysqli_result|false {}

/**
 * Send data in blocks
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param int $param_num Indicates which parameter to associate the data with. Parameters are numbered beginning with 0.
 * @param string $data A string containing data to be sent.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_send_long_data(mysqli_stmt $statement, int $param_num, string $data): bool {}

/**
 * Binds variables to a prepared statement as parameters
 * @param mysqli_stmt $statement A statement identifier returned by mysqli_stmt_init()
 * @param string $types A string that contains one or more characters which specify the types for the corresponding bind variables: Type specification chars Character Description i corresponding variable has type integer d corresponding variable has type double s corresponding variable has type string ...
 * @param mixed &$var1 The number of variables and length of string types must match the parameters in the statement.
 * @param mixed &...$vars
 * @return bool true on success or false on failure.
 */
function mysqli_stmt_bind_param(
    mysqli_stmt $statement,
    string $types,
    mixed &...$vars
): bool {}

/**
 * Binds variables to a prepared statement for result storage
 * @param mysqli_stmt $statement Statement
 * @param mixed &...$vars The variables to be bound.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_bind_result(
    mysqli_stmt $statement,
    mixed &...$vars
): bool {}

/**
 * Fetch results from a prepared statement into the bound variables
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool|null Value Description true Success. Data has been fetched false Error occurred null No more rows/data exists or data truncation occurred
 */
function mysqli_stmt_fetch(mysqli_stmt $statement): ?bool {}

/**
 * Frees stored result memory for the given statement handle
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return void No value is returned.
 */
function mysqli_stmt_free_result(mysqli_stmt $statement): void {}

/**
 * Gets a result set from a prepared statement as a mysqli_result object
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return mysqli_result|false Returns false on failure. For successful queries which produce a result set, such as SELECT, SHOW, DESCRIBE or EXPLAIN, mysqli_stmt_get_result() will return a mysqli_result object. For other successful queries, mysqli_stmt_get_result() will return false.
 */
function mysqli_stmt_get_result(mysqli_stmt $statement): mysqli_result|false {}

/**
 * Get result of SHOW WARNINGS
 * @param mysqli_stmt $statement
 * @return mysqli_warning|false (not documented, but it's probably a mysqli_warning object)
 */
function mysqli_stmt_get_warnings(mysqli_stmt $statement): mysqli_warning|false {}

/**
 * Get the ID generated from the previous INSERT operation
 * @param mysqli_stmt $statement
 * @return string|int
 */
function mysqli_stmt_insert_id(mysqli_stmt $statement): string|int {}

/**
 * Resets a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_reset(mysqli_stmt $statement): bool {}

/**
 * Returns the number of parameter for the given statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return int Returns an integer representing the number of parameters.
 */
function mysqli_stmt_param_count(mysqli_stmt $statement): int {}

/**
 * Returns the SQLSTATE error from previous MySQL operation
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string Returns a string containing the SQLSTATE error code for the last error. The error code consists of five characters. '00000' means no error.
 */
function mysqli_sqlstate(mysqli $mysql): string {}

/**
 * Gets the current system status
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string|false A string describing the server status. FALSE if an error occurred.
 */
function mysqli_stat(mysqli $mysql): string|false {}

/**
 * Used for establishing secure connections using SSL
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string|null $key The path name to the key file
 * @param string|null $certificate The path name to the certificate file
 * @param string|null $ca_certificate The path name to the certificate authority file
 * @param string|null $ca_path The pathname to a directory that contains trusted SSL CA certificates in PEM format
 * @param string|null $cipher_algos A list of allowable ciphers to use for SSL encryption
 * @return bool This function always returns TRUE value.
 */
function mysqli_ssl_set(
    mysqli $mysql,
    string|null $key,
    string|null $certificate,
    string|null $ca_certificate,
    string|null $ca_path,
    string|null $cipher_algos
): true {}

/**
 * Closes a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool Always returns true.
 */
function mysqli_stmt_close(mysqli_stmt $statement): true {}

/**
 * Seeks to an arbitrary row in statement result set
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @param int $offset Must be between zero and the total number of rows minus one (0.. mysqli_stmt_num_rows - 1).
 * @return void No value is returned.
 */
function mysqli_stmt_data_seek(mysqli_stmt $statement, int $offset): void {}

/**
 * Returns the error code for the most recent statement call
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return int An error code value. Zero means no error occurred.
 */
function mysqli_stmt_errno(mysqli_stmt $statement): int {}

/**
 * Returns a string description for last statement error
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return string A string that describes the error. An empty string if no error occurred.
 */
function mysqli_stmt_error(mysqli_stmt $statement): string {}

/**
 * Check if there are more query results from a multiple query
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool Returns true if more results exist, otherwise false.
 */
function mysqli_stmt_more_results(mysqli_stmt $statement): bool {}

/**
 * Reads the next result from a multiple query
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_next_result(mysqli_stmt $statement): bool {}

/**
 * Return the number of rows in statements result set
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return string|int An integer representing the number of buffered rows. Returns 0 in unbuffered mode unless all rows have been fetched from the server. If the number of rows is greater than PHP_INT_MAX, the number will be returned as a string.
 */
function mysqli_stmt_num_rows(mysqli_stmt $statement): string|int {}

/**
 * Returns SQLSTATE error from previous statement operation
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return string Returns a string containing the SQLSTATE error code for the last error. The error code consists of five characters. '00000' means no error.
 */
function mysqli_stmt_sqlstate(mysqli_stmt $statement): string {}

/**
 * Transfers a result set from a prepared statement
 * @param mysqli_stmt $statement Procedural style only: A mysqli_stmt object returned by mysqli_stmt_init.
 * @return bool Returns true on success or false on failure.
 */
function mysqli_stmt_store_result(mysqli_stmt $statement): bool {}

/**
 * Transfers a result set from the last query
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $mode [optional] The option that you want to set
 * @return mysqli_result|false Returns a buffered result object or false if an error occurred. mysqli_store_result returns false in case the query didn't return a result set (if the query was, for example an INSERT statement). This function also returns false if the reading of the result set failed. ...
 */
function mysqli_store_result(mysqli $mysql, int $mode = 0): mysqli_result|false {}

/**
 * Returns the thread ID for the current connection
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int Returns the Thread ID for the current connection.
 */
function mysqli_thread_id(mysqli $mysql): int {}

/**
 * Returns whether thread safety is given or not
 * @return bool true if the client library is thread-safe, otherwise false.
 */
function mysqli_thread_safe(): bool {}

/**
 * Initiate a result set retrieval
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return mysqli_result|false Returns an unbuffered result object or false if an error occurred.
 */
function mysqli_use_result(mysqli $mysql): mysqli_result|false {}

/**
 * Returns the number of warnings from the last query for the given link
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return int Number of warnings or zero if there are no warnings.
 */
function mysqli_warning_count(mysqli $mysql): int {}

/**
 * Flushes tables or caches, or resets the replication server information
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $flags The options to refresh, using the MYSQLI_REFRESH_* constants as documented within the MySQLi constants documentation. See also the official MySQL Refresh documentation.
 * @return bool true if the refresh was a success, otherwise false
 */
function mysqli_refresh(mysqli $mysql, int $flags): bool {}

/**
 * Alias for mysqli_stmt_bind_param
 * @param mysqli_stmt $statement
 * @param string $types
 * @removed 5.4
 * @deprecated
 */
function mysqli_bind_param(mysqli_stmt $statement, string $types) {}

/**
 * Alias for mysqli_stmt_bind_result
 * @param mysqli_stmt $statement
 * @param string $types
 * @param mixed &$var1
 * @removed 5.4
 * @deprecated
 */
function mysqli_bind_result(mysqli_stmt $statement, string $types, mixed &$var1) {}

/**
 * Alias of mysqli_character_set_name
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @return string
 * @removed 5.4
 * @deprecated
 */
function mysqli_client_encoding(mysqli $mysql): string {}

/**
 * Alias of mysqli_real_escape_string
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param string $string The string to be escaped
 * @return string
 */
function mysqli_escape_string(
    mysqli $mysql,
    string $string
): string {}

/**
 * Alias for mysqli_stmt_fetch
 * @param mysqli_stmt $statement
 * @return bool
 * @removed 5.4
 * @deprecated
 */
function mysqli_fetch(mysqli_stmt $statement): bool {}

/**
 * Alias for mysqli_stmt_param_count
 * @param mysqli_stmt $statement
 * @return int
 * @removed 5.4
 * @deprecated
 */
function mysqli_param_count(mysqli_stmt $statement): int {}

/**
 * Alias for mysqli_stmt_result_metadata
 * @param mysqli_stmt $statement
 * @return mysqli_result|false Returns a result object or FALSE if an error occurred
 * @removed 5.4
 * @deprecated
 */
function mysqli_get_metadata(mysqli_stmt $statement): false|mysqli_result {}

/**
 * Alias for mysqli_stmt_send_long_data
 * @param mysqli_stmt $statement
 * @param int $param_num
 * @param string $data
 * @return bool
 * @removed 5.4
 * @deprecated
 */
function mysqli_send_long_data(mysqli_stmt $statement, int $param_num, string $data): bool {}

/**
 * Alias of mysqli_options
 * @param mysqli $mysql A link identifier returned by mysqli_connect() or mysqli_init()
 * @param int $option
 * @param string|int $value
 * @return bool
 */
function mysqli_set_opt(
    mysqli $mysql,
    int $option,
    $value
): bool {}

/**
 * Escapes special characters in a string for use in an SQL statement, taking into account the current charset of the connection
 * @param mysqli $mysql
 * @param string $string
 * @return string
 * @since 8.6
 */
function mysqli_quote_string(mysqli $mysql, string $string): string {}
