<?php

/**
 * Open a PostgreSQL connection
 * @param string $connection_string The connection_string can be empty to use all default parameters, or it can contain one or more parameter settings separated by whitespace. Each parameter setting is in the form keyword = value. Spaces around the equal sign are optional. To write an empty value or a ...
 * @param int $flags If PGSQL_CONNECT_FORCE_NEW is passed, then a new connection is created, even if the connection_string is identical to an existing connection.
 * @return resource|false PostgreSQL connection resource on success, FALSE on failure.
 */
function pg_connect(
    string $connection_string,
    int $flags = 0,
    string $dbname = '',
): \PgSql\Connection|false {}

/**
 * Open a persistent PostgreSQL connection
 * @param string $connection_string The connection_string can be empty to use all default parameters, or it can contain one or more parameter settings separated by whitespace. Each parameter setting is in the form keyword = value. Spaces around the equal sign are optional. To write an empty value or a ...
 * @param int $flags If PGSQL_CONNECT_FORCE_NEW is passed, then a new connection is created, even if the connection_string is identical to an existing connection.
 * @return resource|false PostgreSQL connection resource on success, FALSE on failure.
 */
function pg_pconnect(
    string $connection_string,
    int $flags = 0,
    string $dbname = '',
): \PgSql\Connection|false {}

/**
 * Closes a PostgreSQL connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 */
function pg_close(\PgSql\Connection|null $connection = null): true {}

/**
 * Poll the status of an in-progress asynchronous PostgreSQL connection attempt.
 * @param resource $connection PostgreSQL database connection resource.
 * @return int PGSQL_POLLING_FAILED, PGSQL_POLLING_READING, PGSQL_POLLING_WRITING, PGSQL_POLLING_OK, or PGSQL_POLLING_ACTIVE.
 * @since 5.6
 */
function pg_connect_poll(
    \PgSql\Connection $connection
): int {}

/**
 * Get connection status
 * @param resource $connection PostgreSQL database connection resource.
 * @return int PGSQL_CONNECTION_OK or PGSQL_CONNECTION_BAD.
 */
function pg_connection_status(\PgSql\Connection $connection): int {}

/**
 * Get connection is busy or not
 * @param resource $connection PostgreSQL database connection resource.
 * @return bool TRUE if the connection is busy, FALSE otherwise.
 */
function pg_connection_busy(\PgSql\Connection $connection): bool {}

/**
 * Reset connection (reconnect)
 * @param resource $connection PostgreSQL database connection resource.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_connection_reset(\PgSql\Connection $connection): bool {}

/**
 * Get a read only handle to the socket underlying a PostgreSQL connection
 * @param resource $connection PostgreSQL database connection resource.
 * @return resource|false A socket resource on success or FALSE on failure.
 * @since 5.6
 */
function pg_socket(\PgSql\Connection $connection) {}

/**
 * Returns the host name associated with the connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string|false A string containing the name of the host the connection is to, or FALSE on error.
 */
function pg_host(\PgSql\Connection|null $connection = null): string {}

/**
 * Get the database name
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string|false A string containing the name of the database the connection is to, or FALSE on error.
 */
function pg_dbname(\PgSql\Connection|null $connection = null): string {}

/**
 * Return the port number associated with the connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string A string containing the port number of the database server the connection is to, or empty string on error.
 */
function pg_port(\PgSql\Connection|null $connection = null): string {}

/**
 * Return the TTY name associated with the connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string A string containing the debug TTY of the connection, or FALSE on error.
 */
function pg_tty(\PgSql\Connection|null $connection = null): string {}

/**
 * Get the options associated with the connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string A string containing the connection options, or FALSE on error.
 */
function pg_options(\PgSql\Connection|null $connection = null): string {}

/**
 * Returns an array with client, protocol and server version (when available)
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return array an array with client, protocol and server keys and values (if available). Returns FALSE on error or invalid connection.
 */
function pg_version(\PgSql\Connection|null $connection = null): array {}

/**
 * Ping database connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_ping(\PgSql\Connection|null $connection = null): bool {}

/**
 * Looks up a current parameter setting of the server.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $name [optional] Possible param_name values include server_version, server_encoding, client_encoding, is_superuser, session_authorization, DateStyle, TimeZone, and integer_datetimes.
 * @return string|false A string containing the value of the parameter, FALSE on failure or invalid param_name.
 */
function pg_parameter_status(\PgSql\Connection $connection = null, string $name): string|false {}

/**
 * Returns the current in-transaction status of the server.
 * @param resource $connection PostgreSQL database connection resource.
 * @return int The status can be PGSQL_TRANSACTION_IDLE (currently idle), PGSQL_TRANSACTION_ACTIVE (a command is in progress), PGSQL_TRANSACTION_INTRANS (idle, in a valid transaction block), or PGSQL_TRANSACTION_INERROR (idle, in a failed transaction block). PGSQL_TRANSACTION_UNKNOWN is reported if ...
 */
function pg_transaction_status(\PgSql\Connection $connection): int {}

/**
 * Execute a query
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $query [optional] The SQL statement or statements to be executed. When multiple statements are passed to the function, they are automatically executed as one transaction, unless there are explicit BEGIN/COMMIT commands included in the query string. However, using multiple transactions ...
 * @return resource|false A query result resource on success or FALSE on failure.
 */
function pg_query(
    \PgSql\Connection $connection,
    string $query
): \PgSql\Result|false {}

/**
 * Submits a command to the server and waits for the result, with the ability to pass parameters separately from the SQL command text.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $query The parameterized SQL statement. Must contain only a single statement. (multiple statements separated by semi-colons are not allowed.) If any parameters are used, they are referred to as $1, $2, etc. User-supplied values should always be passed as parameters, not interpolated ...
 * @param array $params [optional] An array of parameter values to substitute for the $1, $2, etc. placeholders in the original prepared query string. The number of elements in the array must match the number of placeholders. Values intended for bytea fields are not supported as parameters. Use ...
 * @return resource|false A query result resource on success or FALSE on failure.
 */
function pg_query_params(
    \PgSql\Connection $connection,
    $query,
    array $params
): \PgSql\Result|false {}

/**
 * Submits a request to create a prepared statement with the
 * given parameters, and waits for completion.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $statement_name The name to give the prepared statement. Must be unique per-connection. If "" is specified, then an unnamed statement is created, overwriting any previously defined unnamed statement.
 * @param string $query [optional] The parameterized SQL statement. Must contain only a single statement. (multiple statements separated by semi-colons are not allowed.) If any parameters are used, they are referred to as $1, $2, etc.
 * @return resource|false A query result resource on success or FALSE on failure.
 */
function pg_prepare(
    \PgSql\Connection $connection,
    string $statement_name,
    string $query
): \PgSql\Result|false {}

/**
 * Sends a request to execute a prepared statement with given parameters, and waits for the result.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $statement_name The name of the prepared statement to execute. if "" is specified, then the unnamed statement is executed. The name must have been previously prepared using pg_prepare, pg_send_prepare or a PREPARE SQL command.
 * @param array $params [optional] An array of parameter values to substitute for the $1, $2, etc. placeholders in the original prepared query string. The number of elements in the array must match the number of placeholders. Elements are converted to strings by calling this function.
 * @return resource|false A query result resource on success or FALSE on failure.
 */
function pg_execute(
    \PgSql\Connection $connection,
    $statement_name,
    array $params
): \PgSql\Result|false {}

/**
 * Sends asynchronous query
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $query The SQL statement or statements to be executed. Data inside the query should be properly escaped.
 * @return int|bool TRUE on success or FALSE on failure. Use pg_get_result to determine the query result.
 */
function pg_send_query(
    \PgSql\Connection $connection,
    string $query
): int|bool {}

/**
 * Submits a command and separate parameters to the server without waiting for the result(s).
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $query The parameterized SQL statement. Must contain only a single statement. (multiple statements separated by semi-colons are not allowed.) If any parameters are used, they are referred to as $1, $2, etc.
 * @param array $params An array of parameter values to substitute for the $1, $2, etc. placeholders in the original prepared query string. The number of elements in the array must match the number of placeholders.
 * @return int|bool TRUE on success or FALSE on failure. Use pg_get_result to determine the query result.
 */
function pg_send_query_params(
    \PgSql\Connection $connection,
    string $query,
    array $params
): int|bool {}

/**
 * Sends a request to create a prepared statement with the given parameters, without waiting for completion.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $statement_name The name to give the prepared statement. Must be unique per-connection. If "" is specified, then an unnamed statement is created, overwriting any previously defined unnamed statement.
 * @param string $query The parameterized SQL statement. Must contain only a single statement. (multiple statements separated by semi-colons are not allowed.) If any parameters are used, they are referred to as $1, $2, etc.
 * @return int|bool TRUE on success, FALSE on failure. Use pg_get_result to determine the query result.
 */
function pg_send_prepare(
    \PgSql\Connection $connection,
    string $statement_name,
    string $query
): int|bool {}

/**
 * Sends a request to execute a prepared statement with given parameters, without waiting for the result(s).
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $statement_name The name of the prepared statement to execute. if "" is specified, then the unnamed statement is executed. The name must have been previously prepared using pg_prepare, pg_send_prepare or a PREPARE SQL command.
 * @param array $params An array of parameter values to substitute for the $1, $2, etc. placeholders in the original prepared query string. The number of elements in the array must match the number of placeholders.
 * @return int|bool TRUE on success, FALSE on failure. Use pg_get_result to determine the query result.
 */
function pg_send_execute(
    \PgSql\Connection $connection,
    string $statement_name,
    array $params
): int|bool {}

/**
 * Cancel an asynchronous query
 * @param resource $connection PostgreSQL database connection resource.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_cancel_query(\PgSql\Connection $connection): bool {}

/**
 * Returns values from a result resource
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row Row number in result to fetch. Rows are numbered from 0 upwards. If omitted, next row is fetched.
 * @param mixed $field [optional] A string representing the name of the field (column) to fetch, otherwise an int representing the field number to fetch. Fields are numbered from 0 upwards.
 * @return string|false|null Boolean is returned as "t" or "f". All other types, including arrays are returned as strings formatted in the same default PostgreSQL manner that you would see in the psql program. Database NULL values are returned as NULL. FALSE is returned if row exceeds the number of ...
 */
function pg_fetch_result(
    \PgSql\Result $result,
    $row,
    string|int $field
): string|false|null {}

/**
 * Get a row as an enumerated array
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row [optional] Row number in result to fetch. Rows are numbered from 0 upwards. If omitted or NULL, the next row is fetched.
 * @param int $mode [optional]
 * @return array|false An array, indexed from 0 upwards, with each value represented as a string. Database NULL values are returned as NULL. FALSE is returned if row exceeds the number of rows in the set, there are no more rows, or on any other error.
 */
function pg_fetch_row(\PgSql\Result $result, ?int $row = null, int $mode = 2): array|false {}

/**
 * Fetch a row as an associative array
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row [optional] Row number in result to fetch. Rows are numbered from 0 upwards. If omitted or NULL, the next row is fetched.
 * @return array|false An array indexed associatively (by field name). Each value in the array is represented as a string. Database NULL values are returned as NULL. FALSE is returned if row exceeds the number of rows in the set, there are no more rows, or on any other error.
 */
function pg_fetch_assoc(\PgSql\Result $result, ?int $row = null): array|false {}

/**
 * Fetch a row as an array
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row [optional] Row number in result to fetch. Rows are numbered from 0 upwards. If omitted or NULL, the next row is fetched.
 * @param int $mode [optional] An optional parameter that controls how the returned array is indexed. result_type is a constant and can take the following values: PGSQL_ASSOC, PGSQL_NUM and PGSQL_BOTH. Using PGSQL_NUM, pg_fetch_array will return an array with numerical indices, using PGSQL_ASSOC it ...
 * @return array|false An array indexed numerically (beginning with 0) or associatively (indexed by field name), or both. Each value in the array is represented as a string. Database NULL values are returned as NULL. FALSE is returned if row exceeds the number of rows in the set, there are no more ...
 */
function pg_fetch_array(\PgSql\Result $result, ?int $row = null, int $mode = PGSQL_BOTH): array|false {}

/**
 * Fetch a row as an object
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int|null $row [optional] Row number in result to fetch. Rows are numbered from 0 upwards. If omitted or NULL, the next row is fetched.
 * @param string $class [optional] Ignored and deprecated.
 * @param array $constructor_args [optional]
 * @return object|false An object with one attribute for each field name in the result. Database NULL values are returned as NULL. FALSE is returned if row exceeds the number of rows in the set, there are no more rows, or on any other error.
 * @throws \ValueError A ValueError is thrown when the constructor_args is non-empty with the class not having a constructor.
 */
function pg_fetch_object(
    \PgSql\Result $result,
    ?int $row = null,
    string $class = 'stdClass',
    array $constructor_args = []
): object|false {}

/**
 * Fetches all rows from a result as an array
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $mode [optional] An optional parameter that controls how the returned array is indexed. result_type is a constant and can take the following values: PGSQL_ASSOC, PGSQL_NUM and PGSQL_BOTH. Using PGSQL_NUM, pg_fetch_array will return an array with numerical indices, using PGSQL_ASSOC it ...
 * @return array|false An array with all rows in the result. Each row is an array of field values indexed by field name. FALSE is returned if there are no rows in the result, or on any other error.
 */
function pg_fetch_all(\PgSql\Result $result, int $mode = PGSQL_ASSOC): array {}

/**
 * Fetches all rows in a particular result column as an array
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field [optional] Column number, zero-based, to be retrieved from the result resource. Defaults to the first column if not specified.
 * @return array An array with all values in the result column. FALSE is returned if column is larger than the number of columns in the result, or on any other error.
 */
function pg_fetch_all_columns(\PgSql\Result $result, int $field = 0): array {}

/**
 * Returns number of affected records (tuples)
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return int The number of rows affected by the query. If no tuple is affected, it will return 0.
 */
function pg_affected_rows(\PgSql\Result $result): int {}

/**
 * Get asynchronous query result
 * @param resource $connection PostgreSQL database connection resource.
 * @return resource|false The result resource, or FALSE if no more results are available.
 */
function pg_get_result(\PgSql\Connection $connection): \PgSql\Result|false {}

/**
 * Set internal row offset in result resource
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row Row to move the internal offset to in the result resource. Rows are numbered starting from zero.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_result_seek(\PgSql\Result $result, int $row): bool {}

/**
 * Get status of query result
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $mode [optional] Either PGSQL_STATUS_LONG to return the numeric status of the result, or PGSQL_STATUS_STRING to return the command tag of the result. If not specified, PGSQL_STATUS_LONG is the default.
 * @return string|int Possible return values are PGSQL_EMPTY_QUERY, PGSQL_COMMAND_OK, PGSQL_TUPLES_OK, PGSQL_COPY_OUT, PGSQL_COPY_IN, PGSQL_BAD_RESPONSE, PGSQL_NONFATAL_ERROR and PGSQL_FATAL_ERROR if PGSQL_STATUS_LONG is specified. Otherwise, a string containing the PostgreSQL command tag is returned.
 */
function pg_result_status(\PgSql\Result $result, int $mode = PGSQL_STATUS_LONG): string|int {}

/**
 * Free result memory
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_free_result(\PgSql\Result $result): bool {}

/**
 * Returns the last row's OID
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return string|int|false A string containing the OID assigned to the most recently inserted row in the specified connection, or FALSE on error or no available OID.
 */
function pg_last_oid(\PgSql\Result $result): string|int|false {}

/**
 * Returns the number of rows in a result
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return int The number of rows in the result. On error, -1 is returned.
 */
function pg_num_rows(\PgSql\Result $result): int {}

/**
 * Returns the number of fields in a result
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return int The number of fields (columns) in the result. On error, -1 is returned.
 */
function pg_num_fields(\PgSql\Result $result): int {}

/**
 * Returns the name of a field
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field Field number, starting from 0.
 * @return string|false The field name, or FALSE on error.
 */
function pg_field_name(\PgSql\Result $result, int $field): string {}

/**
 * Returns the field number of the named field
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param string $field The name of the field.
 * @return int The field number (numbered from 0), or -1 on error.
 */
function pg_field_num(\PgSql\Result $result, string $field): int {}

/**
 * Returns the internal storage size of the named field
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field Field number, starting from 0.
 * @return int The internal field storage size (in bytes). -1 indicates a variable length field. FALSE is returned on error.
 */
function pg_field_size(\PgSql\Result $result, int $field): int {}

/**
 * Returns the type name for the corresponding field number
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field Field number, starting from 0.
 * @return string|false A string containing the base name of the field's type, or FALSE on error.
 */
function pg_field_type(\PgSql\Result $result, int $field): string {}

/**
 * Returns the type ID (OID) for the corresponding field number
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field Field number, starting from 0.
 * @return string|int The OID of the field's base type. FALSE is returned on error.
 */
function pg_field_type_oid(\PgSql\Result $result, int $field): string|int {}

/**
 * Returns the printed length
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row Row number in result. Rows are numbered from 0 upwards. If omitted, current row is fetched.
 * @param mixed $field [optional]
 * @return int|false The field printed length, or FALSE on error.
 */
function pg_field_prtlen(
    \PgSql\Result $result,
    $row,
    string|int $field
): int|false {}

/**
 * Test if a field is SQL NULL
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $row Row number in result to fetch. Rows are numbered from 0 upwards. If omitted, current row is fetched.
 * @param mixed $field [optional] Field number (starting from 0) as an integer or the field name as a string.
 * @return int|false 1 if the field in the given row is SQL NULL, 0 if not. FALSE is returned if the row is out of range, or upon any other error.
 */
function pg_field_is_null(
    \PgSql\Result $result,
    $row,
    string|int $field
): int|false {}

/**
 * Returns the name or oid of the tables field
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @param int $field Field number, starting from 0.
 * @param bool $oid_only [optional] By default the tables name that field belongs to is returned but if oid_only is set to TRUE, then the oid will instead be returned.
 * @return string|int|false On success either the fields table name or oid. Or, FALSE on failure.
 */
function pg_field_table(\PgSql\Result $result, int $field, bool $oid_only = false): string|int|false {}

/**
 * Gets SQL NOTIFY message
 * @param resource $connection PostgreSQL database connection resource.
 * @param int $mode [optional] An optional parameter that controls how the returned array is indexed. result_type is a constant and can take the following values: PGSQL_ASSOC, PGSQL_NUM and PGSQL_BOTH. Using PGSQL_NUM, pg_get_notify will return an array with numerical indices, using PGSQL_ASSOC it ...
 * @return array|false An array containing the NOTIFY message name and backend PID. Otherwise if no NOTIFY is waiting, then FALSE is returned.
 */
function pg_get_notify(
    \PgSql\Connection $connection,
    int $mode = 1
): array|false {}

/**
 * Gets the backend's process ID
 * @param resource $connection PostgreSQL database connection resource.
 * @return int The backend database process ID.
 */
function pg_get_pid(
    \PgSql\Connection $connection,
): int {}

/**
 * Get error message associated with result
 * @param resource $result PostgreSQL query result resource, returned by pg_query, pg_query_params or pg_execute (among others).
 * @return string|false a string if there is an error associated with the result parameter, FALSE otherwise.
 */
function pg_result_error(\PgSql\Result $result): string|false {}

/**
 * Returns an individual field of an error report.
 * @param resource $result A PostgreSQL query result resource from a previously executed statement.
 * @param int $field_code Possible fieldcode values are: PGSQL_DIAG_SEVERITY, PGSQL_DIAG_SQLSTATE, PGSQL_DIAG_MESSAGE_PRIMARY, PGSQL_DIAG_MESSAGE_DETAIL, PGSQL_DIAG_MESSAGE_HINT, PGSQL_DIAG_STATEMENT_POSITION, PGSQL_DIAG_INTERNAL_POSITION (PostgreSQL 8.0+ only), PGSQL_DIAG_INTERNAL_QUERY (PostgreSQL ...
 * @return string|null|false A string containing the contents of the error field, NULL if the field does not exist or FALSE on failure.
 */
function pg_result_error_field(
    \PgSql\Result $result,
    int $field_code
): string|false|null {}

/**
 * Get the last error message string of a connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string A string containing the last error message on the given connection, or FALSE on error.
 */
function pg_last_error(\PgSql\Connection|null $connection = null): string {}

/**
 * Returns the last notice message from PostgreSQL server
 * @param resource $connection PostgreSQL database connection resource.
 * @param int $mode [optional] One of PGSQL_NOTICE_LAST (to return last notice), PGSQL_NOTICE_ALL (to return all notices), or PGSQL_NOTICE_CLEAR (to clear notices).
 * @return array|string|bool A string containing the last notice on the given connection with PGSQL_NOTICE_LAST, an array with PGSQL_NOTICE_ALL, a bool with PGSQL_NOTICE_CLEAR, or FALSE on error.
 */
function pg_last_notice(\PgSql\Connection $connection, int $mode = PGSQL_NOTICE_LAST): array|string|bool {}

/**
 * Send a NULL-terminated string to PostgreSQL backend
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $query [optional] A line of text to be sent directly to the PostgreSQL backend. A NULL terminator is added automatically.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_put_line(
    \PgSql\Connection $connection = null,
    string $query
): bool {}

/**
 * Sync with PostgreSQL backend
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_end_copy(\PgSql\Connection|null $connection = null): bool {}

/**
 * Copy a table to an array
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table from which to copy the data into rows.
 * @param string $separator [optional] The token that separates values for each field in each element of rows. Default is TAB.
 * @param string $null_as [optional] How SQL NULL values are represented in the rows. Default is \N ("\\N").
 * @return array|false An array with one element for each line of COPY data. It returns FALSE on failure.
 */
function pg_copy_to(
    \PgSql\Connection $connection,
    string $table_name,
    string $separator = '	',
    string $null_as = '\\\\N'
): array|false {}

/**
 * Insert records into a table from an array
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table into which to copy the rows.
 * @param array $rows An array of data to be copied into table_name. Each value in rows becomes a row in table_name. Each value in rows should be a delimited string of the values to insert into each field. Values should be linefeed terminated.
 * @param string $separator [optional] The token that separates values for each field in each element of rows. Default is TAB.
 * @param string $null_as [optional] How SQL NULL values are represented in the rows. Default is \N ("\\N").
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_copy_from(
    \PgSql\Connection $connection,
    string $table_name,
    array $rows,
    string $separator = '	',
    string $null_as = '\\\\N'
): bool {}

/**
 * Enable tracing a PostgreSQL connection
 * @param string $filename The full path and file name of the file in which to write the trace log. Same as in fopen.
 * @param string $mode [optional] An optional file access mode, same as for fopen.
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param int $trace_mode Since PHP 8.3 optional trace mode
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_trace(
    string $filename,
    string $mode = "w",
    \PgSql\Connection|null $connection = null,
    int $trace_mode = 0
): bool {}

/**
 * Disable tracing of a PostgreSQL connection
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 */
function pg_untrace(\PgSql\Connection|null $connection = null): true {}

/**
 * Create a large object
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param mixed $oid [optional] If an object_id is given the function will try to create a large object with this id, else a free object id is assigned by the server. The parameter was added in PHP 5.3 and relies on functionality that first appeared in PostgreSQL 8.1.
 * @return string|int|false A large object OID or FALSE on error.
 */
function pg_lo_create(\PgSql\Connection $connection, $oid): string|int|false {}

/**
 * Delete a large object
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param int $oid [optional] The OID of the large object in the database.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_lo_unlink(
    \PgSql\Connection $connection,
    $oid
): bool {}

/**
 * Open a large object
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param int $oid [optional] The OID of the large object in the database.
 * @param string $mode [optional] Can be either "r" for read-only, "w" for write only or "rw" for read and write.
 * @return resource|false A large object resource or FALSE on error.
 */
function pg_lo_open(
    \PgSql\Connection $connection,
    $oid,
    string $mode
): \PgSql\Lob|false {}

/**
 * Close a large object
 * @param resource $lob An PgSql\Lob instance, returned by pg_lo_open.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_lo_close(\PgSql\Lob $lob): bool {}

/**
 * Read a large object
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @param int $length [optional] An optional maximum number of bytes to return.
 * @return string|false A string containing len bytes from the large object, or FALSE on error.
 */
function pg_lo_read(\PgSql\Lob $lob, int $length = 8192): string|false {}

/**
 * Write to a large object
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @param string $data The data to be written to the large object. If len is specified and is less than the length of data, only len bytes will be written.
 * @param int $length [optional] An optional maximum number of bytes to write. Must be greater than zero and no greater than the length of data. Defaults to the length of data.
 * @return int|false The number of bytes written to the large object, or FALSE on error.
 */
function pg_lo_write(\PgSql\Lob $lob, string $data, ?int $length = null): int|false {}

/**
 * Reads an entire large object and send straight to browser
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @return int|false Number of bytes read or FALSE on error.
 */
function pg_lo_read_all(\PgSql\Lob $lob): int {}

/**
 * Import a large object from file
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $filename The full path and file name of the file on the client filesystem from which to read the large object data.
 * @param int|string $oid If an oid is given the function will try to create a large object with this id, else a free object id is assigned by the server. The parameter relies on functionality that first appeared in PostgreSQL 8.1.
 * @return string|int|false The OID of the newly created large object, or FALSE on failure.
 */
function pg_lo_import(
    \PgSql\Connection $connection,
    $filename = null,
    $oid = null
): string|int|false {}

/**
 * Export a large object to file
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param int $oid The OID of the large object in the database.
 * @param string $filename The full path and file name of the file in which to write the large object on the client filesystem.
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_lo_export(
    \PgSql\Connection $connection,
    $oid = null,
    $filename = null
): bool {}

/**
 * Seeks position within a large object
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @param int $offset The number of bytes to seek.
 * @param int $whence [optional] One of the constants PGSQL_SEEK_SET (seek from object start), PGSQL_SEEK_CUR (seek from current position) or PGSQL_SEEK_END (seek from object end) .
 * @return bool TRUE on success or FALSE on failure.
 */
function pg_lo_seek(\PgSql\Lob $lob, int $offset, int $whence = PGSQL_SEEK_CUR): bool {}

/**
 * Returns current seek position a of large object
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @return int The current seek offset (in number of bytes) from the beginning of the large object. If there is an error, the return value is negative.
 */
function pg_lo_tell(\PgSql\Lob $lob): int {}

/**
 * Truncates a large object
 * @param resource $lob PostgreSQL large object (LOB) resource, returned by pg_lo_open.
 * @param int $size The number of bytes to truncate.
 * @return bool Returns true on success or false on failure.
 */
function pg_lo_truncate(
    \PgSql\Lob $lob,
    int $size
): bool {}

/**
 * Escape a string for query
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $string [optional] A string containing text to be escaped.
 * @return string A string containing the escaped data.
 */
function pg_escape_string(
    \PgSql\Connection $connection = null,
    string $string
): string {}

/**
 * Escape a string for insertion into a bytea field
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $string [optional] A string containing text or binary data to be inserted into a bytea column.
 * @return string A string containing the escaped data.
 */
function pg_escape_bytea(
    \PgSql\Connection $connection = null,
    string $string
): string {}

/**
 * Escape a identifier for insertion into a text field
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $string [optional] A string containing text to be escaped.
 * @return string|false A string containing the escaped data.
 * @since 5.4.4
 */
function pg_escape_identifier(
    \PgSql\Connection $connection = null,
    string $string
): string|false {}

/**
 * Escape a literal for insertion into a text field
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $string [optional] A string containing text to be escaped.
 * @return string|false A string containing the escaped data.
 * @since 5.4.4
 */
function pg_escape_literal(
    \PgSql\Connection $connection = null,
    string $string
): string|false {}

/**
 * Unescape binary for bytea type
 * @param string $string A string containing PostgreSQL bytea data to be converted into a PHP binary string.
 * @return string A string containing the unescaped data.
 */
function pg_unescape_bytea(string $string): string {}

/**
 * Determines the verbosity of messages returned by pg_last_error
 * and pg_result_error.
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param int $verbosity [optional] The required verbosity: PGSQL_ERRORS_TERSE, PGSQL_ERRORS_DEFAULT or PGSQL_ERRORS_VERBOSE.
 * @return int|false The previous verbosity level: PGSQL_ERRORS_TERSE, PGSQL_ERRORS_DEFAULT or PGSQL_ERRORS_VERBOSE.
 */
function pg_set_error_verbosity(
    \PgSql\Connection $connection,
    int $verbosity
): int|false {}

/**
 * Gets the client encoding
 * @param resource $connection [optional] PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @return string|false The client encoding, or FALSE on error.
 */
function pg_client_encoding(\PgSql\Connection|null $connection = null): string {}

/**
 * Set the client encoding
 * @param resource $connection PostgreSQL database connection resource. When connection is not present, the default connection is used. The default connection is the last connection made by pg_connect or pg_pconnect.
 * @param string $encoding [optional] The required client encoding. One of SQL_ASCII, EUC_JP, EUC_CN, EUC_KR, EUC_TW, UNICODE, MULE_INTERNAL, LATINX (X=1...9), KOI8, WIN, ALT, SJIS, BIG5 or WIN1250. The exact list of available encodings depends on your PostgreSQL version, so check your PostgreSQL ...
 * @return int 0 on success or -1 on error.
 */
function pg_set_client_encoding(
    \PgSql\Connection $connection = null,
    string $encoding
): int {}

/**
 * Get meta data for table
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name The name of the table.
 * @param bool $extended Flag for returning extended meta data. Default to false.
 * @return array|false An array of the table definition, or FALSE on error.
 */
function pg_meta_data(
    \PgSql\Connection $connection,
    string $table_name,
    bool $extended = false
): array|false {}

/**
 * Convert associative array values into suitable for SQL statement
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table against which to convert types.
 * @param array $values Data to be converted.
 * @param int $flags [optional] Any number of PGSQL_CONV_IGNORE_DEFAULT, PGSQL_CONV_FORCE_NULL or PGSQL_CONV_IGNORE_NOT_NULL, combined.
 * @return array|false An array of converted values, or FALSE on error.
 * @throws \ValueError A ValueError or TypeError is thrown when the value or type of field does not match properly with a PostgreSQL's type.
 * @throws \TypeError A ValueError or TypeError is thrown when the value or type of field does not match properly with a PostgreSQL's type.
 */
function pg_convert(
    \PgSql\Connection $connection,
    string $table_name,
    array $values,
    int $flags = 0
): array|false {}

/**
 * Insert array into table
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table into which to insert rows. The table table_name must at least have as many columns as assoc_array has elements.
 * @param array $values An array whose keys are field names in the table table_name, and whose values are the values of those fields that are to be inserted.
 * @param int $flags [optional] Any number of PGSQL_CONV_OPTS, PGSQL_DML_NO_CONV, PGSQL_DML_EXEC, PGSQL_DML_ASYNC or PGSQL_DML_STRING combined. If PGSQL_DML_STRING is part of the options then query string is returned.
 * @return mixed TRUE on success or FALSE on failure. Returns string if PGSQL_DML_STRING is passed via options.
 * @throws \ValueError A ValueError is thrown when the specified table is invalid. A ValueError or TypeError is thrown when the value or type of field does not match properly with a PostgreSQL's type.
 * @throws \TypeError A ValueError or TypeError is thrown when the value or type of field does not match properly with a PostgreSQL's type.
 */
function pg_insert(
    \PgSql\Connection $connection,
    string $table_name,
    array $values,
    int $flags = PGSQL_DML_EXEC
): \PgSql\Result|string|bool {}

/**
 * Update table
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table into which to update rows.
 * @param array $values An array whose keys are field names in the table table_name, and whose values are what matched rows are to be updated to.
 * @param array $conditions An array whose keys are field names in the table table_name, and whose values are the conditions that a row must meet to be updated.
 * @param int $flags [optional] Any number of PGSQL_CONV_OPTS, PGSQL_DML_NO_CONV, PGSQL_DML_EXEC or PGSQL_DML_STRING combined. If PGSQL_DML_STRING is part of the options then query string is returned.
 * @return string|bool TRUE on success or FALSE on failure. Returns string if PGSQL_DML_STRING is passed via options.
 */
function pg_update(
    \PgSql\Connection $connection,
    string $table_name,
    array $values,
    array $conditions,
    int $flags = PGSQL_DML_EXEC
): string|bool {}

/**
 * Deletes records
 * @param resource $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table from which to delete rows.
 * @param array $conditions An array whose keys are field names in the table table_name, and whose values are the values of those fields that are to be deleted.
 * @param int $flags [optional] Any number of PGSQL_CONV_FORCE_NULL, PGSQL_DML_NO_CONV, PGSQL_DML_EXEC or PGSQL_DML_STRING combined. If PGSQL_DML_STRING is part of the options then query string is returned.
 * @return string|bool TRUE on success or FALSE on failure. Returns string if PGSQL_DML_STRING is passed via options.
 */
function pg_delete(
    \PgSql\Connection $connection,
    string $table_name,
    array $conditions,
    int $flags = PGSQL_DML_EXEC
): string|bool {}

/**
 * Select records
 * @param resource|PgSql\Connection $connection PostgreSQL database connection resource.
 * @param string $table_name Name of the table from which to select rows.
 * @param array $conditions An array whose keys are field names in the table table_name, and whose values are the conditions that a row must meet to be retrieved.
 * @param int $flags [optional] Any number of PGSQL_CONV_FORCE_NULL, PGSQL_DML_NO_CONV, PGSQL_DML_EXEC, PGSQL_DML_ASYNC or PGSQL_DML_STRING combined. If PGSQL_DML_STRING is part of the options then query string is returned.
 * @param int $mode [optional] An optional parameter that controls how the returned array is indexed. result_type is a constant and can take the following values: PGSQL_ASSOC, PGSQL_NUM and PGSQL_BOTH. Using PGSQL_NUM, pg_fetch_array will return an array with numerical indices, using PGSQL_ASSOC it ...
 * @return array|string|false TRUE on success or FALSE on failure. Returns string if PGSQL_DML_STRING is passed via options.
 */
function pg_select(
    \PgSql\Connection $connection,
    string $table_name,
    array $conditions = [],
    int $flags = PGSQL_DML_EXEC,
    int $mode = PGSQL_ASSOC
): array|string|false {}

/**
 * @param $connection
 * @param $query [optional]
 * @return mixed
 */
function pg_exec(
    \PgSql\Connection $connection,
    string $query
): \PgSql\Result|false {}

/**
 * @param $result
 * @return string|int|false
 * @deprecated 8.0
 */
function pg_getlastoid(\PgSql\Result $result): string|int|false {}

/**
 * @param $result
 * @return int
 * @deprecated 8.0
 */
function pg_cmdtuples(\PgSql\Result $result): int {}

/**
 * @param $connection [optional]
 * @return string
 * @deprecated 8.0
 */
function pg_errormessage(\PgSql\Connection|null $connection): string {}

/**
 * @param $result
 * @return int
 * @deprecated 8.0
 */
function pg_numrows(\PgSql\Result $result): int {}

/**
 * @param $result
 * @return int
 * @deprecated 8.0
 */
function pg_numfields(\PgSql\Result $result): int {}

/**
 * @param $result
 * @param $field
 * @return string
 * @deprecated 8.0
 */
function pg_fieldname(\PgSql\Result $result, int $field): string {}

/**
 * @param $result
 * @param $field
 * @return int
 * @deprecated 8.0
 */
function pg_fieldsize(\PgSql\Result $result, int $field): int {}

/**
 * @param $result
 * @param $field
 * @return string
 * @deprecated 8.0
 */
function pg_fieldtype(\PgSql\Result $result, int $field): string {}

/**
 * @param $result
 * @param $field
 * @return int
 * @deprecated 8.0
 */
function pg_fieldnum(\PgSql\Result $result, string $field): int {}

/**
 * @param $result
 * @param $row
 * @param $field [optional]
 * @return int|false
 * @deprecated 8.0
 */
function pg_fieldprtlen(
    \PgSql\Result $result,
    $row,
    string|int $field
): int|false {}

/**
 * @param $result
 * @param $row
 * @param $field [optional]
 * @return int|false
 * @deprecated 8.0
 */
function pg_fieldisnull(
    \PgSql\Result $result,
    $row,
    string|int $field
): int|false {}

/**
 * @param $result
 * @return bool
 * @deprecated 8.0
 */
function pg_freeresult(\PgSql\Result $result): bool {}

/**
 * @param PgSql\Result|resource $result
 * @param $row
 * @param $field [optional]
 * @deprecated 8.0
 */
function pg_result(
    \PgSql\Result $result,
    $row,
    string|int $field
): string|null|false {}

/**
 * @param $lob
 * @deprecated 8.0
 */
function pg_loreadall(\PgSql\Lob $lob): int {}

/**
 * @param $connection [optional]
 * @param $oid [optional]
 * @return string|int|false
 * @deprecated 8.0
 */
function pg_locreate(\PgSql\Connection $connection, $oid): string|int|false {}

/**
 * @param $connection
 * @param $oid [optional]
 * @return bool
 * @deprecated 8.0
 */
function pg_lounlink(
    \PgSql\Connection $connection,
    $oid
): bool {}

/**
 * @param $connection
 * @param $oid [optional]
 * @param $mode [optional]
 * @return resource|false
 * @deprecated 8.0
 */
function pg_loopen(
    \PgSql\Connection $connection,
    $oid,
    string $mode
): \PgSql\Lob|false {}

/**
 * @param $lob
 * @return bool
 * @deprecated 8.0
 */
function pg_loclose(\PgSql\Lob $lob): bool {}

/**
 * @param $lob
 * @param $length
 * @return string|false
 * @deprecated 8.0
 */
function pg_loread(\PgSql\Lob $lob, int $length = 8192): string|false {}

/**
 * @param $lob
 * @param $data
 * @param $length [optional]
 * @return int|false
 * @deprecated 8.0
 */
function pg_lowrite(\PgSql\Lob $lob, string $data, ?int $length): int|false {}

/**
 * @param $connection
 * @param $filename [optional]
 * @param $oid [optional]
 * @return string|int|false
 * @deprecated 8.0
 */
function pg_loimport(
    \PgSql\Connection $connection,
    $filename,
    $oid
): string|int|false {}

/**
 * @param $connection
 * @param $oid [optional]
 * @param $filename [optional]
 * @return bool
 * @deprecated 8.0
 */
function pg_loexport(
    \PgSql\Connection $connection,
    $oid,
    $filename
): bool {}

/**
 * @param $connection [optional]
 * @return string
 * @deprecated 8.0
 */
function pg_clientencoding(\PgSql\Connection|null $connection): string {}

/**
 * @param $connection
 * @param $encoding [optional]
 * @return int
 * @deprecated 8.0
 */
function pg_setclientencoding(
    \PgSql\Connection $connection,
    string $encoding
): int {}

/**
 * Reads input on the connection
 * @param PgSql\Connection|resource $connection An PgSql\Connection instance.
 * @return bool true if no error occurred, or false if there was an error. Note that true does not necessarily indicate that input was waiting to be read.
 */
function pg_consume_input(\PgSql\Connection $connection): bool {}

/**
 * Flush outbound query data on the connection
 * @param PgSql\Connection|resource $connection An PgSql\Connection instance.
 * @return int|bool Returns true if the flush was successful or no data was waiting to be flushed, 0 if part of the pending data was flushed but more remains or false on failure.
 */
function pg_flush(\PgSql\Connection $connection): int|bool {}

/**
 * Determines the visibility of the context's error messages returned by pg_last_error and
 * pg_result_error
 * @since 8.3
 */
function pg_set_error_context_visibility(PgSql\Connection $connection, int $visibility): int {}

/**
 * @since 8.3
 */
function pg_pipeline_status(PgSql\Connection $connection): int {}

/**
 * @since 8.3
 */
function pg_pipeline_sync(PgSql\Connection $connection): bool {}

/**
 * @since 8.3
 */
function pg_exit_pipeline_mode(PgSql\Connection $connection): bool {}

/**
 * @since 8.3
 */
function pg_enter_pipeline_mode(PgSql\Connection $connection): bool {}

/**
 * Returns the amount of memory allocated for a query result
 *
 * Returns the amount of memory, in bytes, allocated to the specified query result PgSql\Result
 * instance. This value is the same amount that would be freed by pg_free_result.
 * @since 8.4
 */
function pg_result_memory_size(PgSql\Result $result): int {}

/**
 * Change a PostgreSQL user's password
 *
 * pg_change_password changes the password of a PostgreSQL user. This function uses the
 * PQchangePassword libpq function which handles password encryption automatically based on the
 * server's settings.
 * @since 8.4
 */
function pg_change_password(PgSql\Connection $connection, string $user, string $password): bool {}

/**
 * Send data to the server during a COPY operation
 *
 * Sends data to the server during a COPY FROM STDIN operation. A COPY command must have been issued
 * via pg_query before calling this function.
 * @since 8.4
 */
function pg_put_copy_data(PgSql\Connection $connection, string $cmd): int {}

/**
 * Poll a PostgreSQL connection socket for read/write readiness
 *
 * Polls a PostgreSQL connection socket for read and/or write readiness. The socket can be obtained
 * using pg_socket. This function is useful for implementing non-blocking, asynchronous query
 * workflows.
 * @since  8.4
 * @param resource $socket A socket resource obtained from pg_socket.
 * @param int $read Whether to check for read readiness. Pass 1 to check, 0 to skip.
 * @param int $write Whether to check for write readiness. Pass 1 to check, 0 to skip.
 * @param int $timeout The maximum number of milliseconds to wait. Pass -1 to wait indefinitely, or 0 to not wait at all.
 */
function pg_socket_poll($socket, int $read, int $write, int $timeout = -1): int {}

/**
 * Set the query results to be retrieved in chunk mode
 *
 * Set the query results to be retrieved in chunk mode. The query results returned afterward will be
 * divided into multiple chunks, each containing up to size rows. This function must be called
 * before retrieving results with pg_get_result. This function is only available when libpq is
 * version 17 or higher.
 * @since  8.4
 * @throws \ValueError If size is less than 1, a ValueError will be thrown.
 */
function pg_set_chunked_rows_size(PgSql\Connection $connection, int $size): bool {}

/**
 * Signal the completion of a COPY operation to the server
 *
 * Sends an end-of-data indication to the server during a COPY FROM STDIN operation.
 * @since 8.4
 */
function pg_put_copy_end(PgSql\Connection $connection, ?string $error = null): int {}

/**
 * @since 8.5
 */
function pg_close_stmt(
    Pgsql\Connection $connection,
    string $statement_name
): PgSql\Result|false {}

/**
 * Returns the JIT information of the server
 *
 * pg_jit returns an array with the JIT (Just-In-Time compilation) information of the PostgreSQL
 * server.
 * @since 8.4
 * @return array<string, string|null> Returns an array containing the JIT information of the server.
 */
function pg_jit(?PgSql\Connection $connection = null): array {}
