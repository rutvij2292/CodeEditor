<?php

/**
 * A class that handles prepared statements for the SQLite 3 extension.
 */
class SQLite3Stmt
{
    /**
     * @since 8.5
     */
    public const EXPLAIN_MODE_EXPLAIN_QUERY_PLAN = 2;

    /**
     * @since 8.5
     */
    public const EXPLAIN_MODE_EXPLAIN = 1;

    /**
     * @since 8.5
     */
    public const EXPLAIN_MODE_PREPARED = 0;

    /**
     * Returns the number of parameters within the prepared statement
     * @return int the number of parameters within the prepared statement.
     */
    public function paramCount(): int {}

    /**
     * Closes the prepared statement
     * @return bool TRUE
     * @throws \Error An Error is thrown if the method is called on an uninitialized object.
     */
    public function close(): bool {}

    /**
     * Resets the prepared statement
     * @return bool TRUE if the statement is successfully reset, FALSE on failure.
     */
    public function reset(): bool {}

    /**
     * Clears all current bound parameters
     * @return bool TRUE on successful clearing of bound parameters, FALSE on failure.
     */
    public function clear(): bool {}

    /**
     * Executes a prepared statement and returns a result set object
     * @return SQLite3Result|false an SQLite3Result object on successful execution of the prepared statement, FALSE on failure.
     */
    public function execute(): SQLite3Result|false {}

    /**
     * Binds a parameter to a statement variable
     * @param string $param An string identifying the statement variable to which the parameter should be bound.
     * @param mixed &$var The parameter to bind to a statement variable.
     * @param int $type [optional] The data type of the parameter to bind. SQLITE3_INTEGER: The value is a signed integer, stored in 1, 2, 3, 4, 6, or 8 bytes depending on the magnitude of the value.
     * @return bool TRUE if the parameter is bound to the statement variable, FALSE on failure.
     */
    public function bindParam(
        string|int $param,
        mixed &$var,
        int $type = SQLITE3_TEXT
    ): bool {}

    /**
     * Binds the value of a parameter to a statement variable
     * @param string $param An string identifying the statement variable to which the value should be bound.
     * @param mixed $value The value to bind to a statement variable.
     * @param int $type [optional] The data type of the value to bind. SQLITE3_INTEGER: The value is a signed integer, stored in 1, 2, 3, 4, 6, or 8 bytes depending on the magnitude of the value.
     * @return bool TRUE if the value is bound to the statement variable, FALSE on failure.
     */
    public function bindValue(
        string|int $param,
        mixed $value,
        int $type = SQLITE3_TEXT
    ): bool {}

    /**
     * Returns whether a statement is definitely read only
     *
     * Returns whether a statement is definitely read only. A statement is considered read only, if
     * it makes no direct changes to the content of the database file. Note that user defined SQL
     * functions might change the database indirectly as a side effect.
     * @return bool Returns true if a statement is definitely read only, false otherwise.
     */
    public function readOnly(): bool {}

    /**
     * Constructs an SQLite3Stmt object
     *
     * SQLite3Stmt instances are created by SQLite3::prepare.
     * @param SQLite3 $sqlite3
     * @param string $query
     */
    private function __construct(
        SQLite3 $sqlite3,
        string $query
    ) {}

    /**
     * Retrieves the SQL of the prepared statement. If expanded is FALSE, the unmodified SQL is retrieved.
     * If expanded is TRUE, all query parameters are replaced with their bound values, or with an SQL NULL, if not already bound.
     * @param bool $expand Whether to retrieve the expanded SQL. Passing TRUE is only supported as of libsqlite 3.14.
     * @return string|false Returns the SQL of the prepared statement, or FALSE on failure.
     * @since 7.4
     * @throws \Exception If expand is true, but the libsqlite version is less than 3.14, an error of level E_WARNING or an Exception is issued, according to SQLite3::enableExceptions.
     */
    public function getSQL(bool $expand = false): string|false {}

    /**
     * @since 8.5
     */
    public function busy(): bool {}

    /**
     * @since 8.5
     */
    public function explain(): int {}

    /**
     * @since 8.5
     */
    public function setExplain(int $mode): bool {}
}
