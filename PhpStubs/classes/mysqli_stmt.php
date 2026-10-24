<?php

/**
 * Represents a prepared statement.
 */
class mysqli_stmt
{
    /**
     * @var int
     */
    public int|string $affected_rows;

    /**
     * @var int
     */
    public int|string $insert_id;

    /**
     * @var int
     */
    public int|string $num_rows;

    /**
     * @var int
     */
    public int $param_count;

    /**
     * @var int
     */
    public int $field_count;

    /**
     * @var int
     */
    public int $errno;

    /**
     * @var string
     */
    public string $error;

    /**
     * @var array
     */
    public array $error_list;

    /**
     * @var string
     */
    public string $sqlstate;

    /**
     * @var int
     */
    public int $id;

    /**
     * mysqli_stmt constructor
     * @param mysqli $mysql
     * @param string $query [optional]
     * @throws \mysqli_sql_exception If mysqli error reporting is enabled (MYSQLI_REPORT_ERROR) and the requested operation fails, a warning is generated. If, in addition, the mode is set to MYSQLI_REPORT_STRICT, a mysqli_sql_exception is thrown instead.
     */
    public function __construct(
        mysqli $mysql,
        string|null $query
    ) {}

    /**
     * Used to get the current value of a statement attribute
     * @param int $attribute The attribute that you want to get.
     * @return int Returns the value of the attribute.
     */
    public function attr_get(int $attribute): int {}

    /**
     * Used to modify the behavior of a prepared statement
     * @param int $attribute The attribute that you want to set. It can have one of the following values: Attribute values Character Description MYSQLI_STMT_ATTR_UPDATE_MAX_LENGTH If set to 1, causes mysqli_stmt_store_result to update the metadata MYSQL_FIELD->max_length value. ...
     * @param int $value The value to assign to the attribute.
     * @return bool Returns true on success or false on failure.
     */
    public function attr_set(
        int $attribute,
        int $value
    ): bool {}

    /**
     * Binds variables to a prepared statement as parameters
     * @param string $types A string that contains one or more characters which specify the types for the corresponding bind variables: Type specification chars Character Description i corresponding variable has type integer d corresponding variable has type double s corresponding variable has type string ...
     * @param mixed &$var1 The number of variables and length of string types must match the parameters in the statement.
     * @param mixed &...$_ [optional]
     * @return bool true on success or false on failure.
     */
    public function bind_param(string $types, mixed & $var1, mixed & ...$_): bool {}

    /**
     * Binds variables to a prepared statement for result storage
     * @param mixed &$var1 The variable to be bound.
     * @param mixed &...$_ The variables to be bound.
     * @return bool true on success or false on failure.
     */
    public function bind_result(mixed &$var1, mixed &...$_): bool {}

    /**
     * Closes a prepared statement
     * @return bool true on success or false on failure.
     */
    public function close(): bool {}

    /**
     * Seeks to an arbitrary row in statement result set
     * @param int $offset Must be between zero and the total number of rows minus one (0.. mysqli_stmt_num_rows - 1).
     * @return void No value is returned.
     */
    public function data_seek(int $offset): void {}

    /**
     * Executes a prepared statement
     * @param array|null $params [optional] An optional list array with as many elements as there are bound parameters in the SQL statement being executed. Each value is treated as a string.
     * @return bool true on success or false on failure.
     */
    public function execute(?array $params = null): bool {}

    /**
     * Fetch results from a prepared statement into the bound variables
     * @return bool|null Value Description true Success. Data has been fetched false Error occurred null No more rows/data exists or data truncation occurred
     */
    public function fetch(): ?bool {}

    /**
     * Get result of SHOW WARNINGS
     * @return object|false
     */
    public function get_warnings(): mysqli_warning|false {}

    /**
     * Returns result set metadata from a prepared statement
     * @return mysqli_result|false a result object or false if an error occurred.
     */
    public function result_metadata(): mysqli_result|false {}

    /**
     * Check if there are more query results from a multiple query
     * @return bool Returns true if more results exist, otherwise false.
     */
    public function more_results(): bool {}

    /**
     * Reads the next result from a multiple query
     * @return bool Returns true on success or false on failure.
     */
    public function next_result(): bool {}

    /**
     * Return the number of rows in statements result set
     * @return string|int An integer representing the number of rows in result set.
     */
    public function num_rows(): string|int {}

    /**
     * Send data in blocks
     * @param int $param_num Indicates which parameter to associate the data with. Parameters are numbered beginning with 0.
     * @param string $data A string containing data to be sent.
     * @return bool true on success or false on failure.
     */
    public function send_long_data(
        int $param_num,
        string $data
    ): bool {}

    /**
     * No documentation available
     * @removed 5.4
     * @deprecated
     */
    public function stmt() {}

    /**
     * Frees stored result memory for the given statement handle
     * @return void No value is returned.
     */
    public function free_result(): void {}

    /**
     * Resets a prepared statement
     * @return bool true on success or false on failure.
     */
    public function reset(): bool {}

    /**
     * Prepare an SQL statement for execution
     * @param string $query The query, as a string. It must consist of a single SQL statement. The SQL statement may contain zero or more parameter markers represented by question mark (?) characters at the appropriate positions. The markers are legal only in certain places in SQL statements. For example, ...
     * @return bool true on success or false on failure.
     */
    public function prepare(string $query): bool {}

    /**
     * Stores a result set in an internal buffer
     * @return bool true on success or false on failure.
     */
    public function store_result(): bool {}

    /**
     * Gets a result set from a prepared statement as a mysqli_result object
     * @return mysqli_result|false Returns a resultset or FALSE on failure
     */
    public function get_result(): mysqli_result|false {}
}
