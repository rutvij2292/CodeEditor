<?php

/**
 * Represents a prepared statement and, after the statement is executed, an
 * associated result set.
 */
class PDOStatement implements IteratorAggregate
{
    /**
     * @var string
     */
    public string $queryString;

    /**
     * Executes a prepared statement
     * @param array $params [optional] An array of values with as many elements as there are bound parameters in the SQL statement being executed. All values are treated as PDO::PARAM_STR. You cannot bind multiple values to a single parameter; for example, you cannot bind two values to a single named ...
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function execute(array|null $params = null): bool {}

    /**
     * Fetches the next row from a result set
     * @param int $mode [optional] Controls how the next row will be returned to the caller. This value must be one of the PDO::FETCH_* constants, defaulting to value of PDO::ATTR_DEFAULT_FETCH_MODE (which defaults to PDO::FETCH_BOTH). PDO::FETCH_ASSOC: returns an array indexed by column name as returned ...
     * @param int $cursorOrientation [optional] For a PDOStatement object representing a scrollable cursor, this value determines which row will be returned to the caller. This value must be one of the PDO::FETCH_ORI_* constants, defaulting to PDO::FETCH_ORI_NEXT. To request a scrollable cursor for your ...
     * @param int $cursorOffset [optional]
     * @return ($mode is PDO::FETCH_ASSOC ? array<string, mixed>|false : ($mode is PDO::FETCH_NUM ? list<mixed>|false : ($mode is PDO::FETCH_BOTH ? array<string|int, mixed>|false : ($mode is PDO::FETCH_OBJ ? \stdClass|false : ($mode is PDO::FETCH_COLUMN ? mixed : ($mode is PDO::FETCH_NAMED ? array<string, ...
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function fetch(
            int $mode = PDO::FETCH_DEFAULT,
            int $cursorOrientation = PDO::FETCH_ORI_NEXT,
            int $cursorOffset = 0
        ): mixed {}

    /**
     * Binds a parameter to the specified variable name
     * @param mixed $param Parameter identifier. For a prepared statement using named placeholders, this will be a parameter name of the form :name. For a prepared statement using question mark placeholders, this will be the 1-indexed position of the parameter.
     * @param mixed &$var Name of the PHP variable to bind to the SQL statement parameter.
     * @param int $type [optional] Explicit data type for the parameter using the PDO::PARAM_* constants. To return an INOUT parameter from a stored procedure, use the bitwise OR operator to set the PDO::PARAM_INPUT_OUTPUT bits for the data_type parameter.
     * @param int $maxLength [optional] Length of the data type. To indicate that a parameter is an OUT parameter from a stored procedure, you must explicitly set the length.
     * @param mixed $driverOptions [optional]
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function bindParam(
            int|string $param,
            mixed &$var,
            int $type = PDO::PARAM_STR,
            int $maxLength = 0,
            mixed $driverOptions = null
        ): bool {}

    /**
     * Bind a column to a PHP variable
     * @param mixed $column Number of the column (1-indexed) or name of the column in the result set. If using the column name, be aware that the name should match the case of the column, as returned by the driver.
     * @param mixed &$var Name of the PHP variable to which the column will be bound.
     * @param int $type [optional] Data type of the parameter, specified by the PDO::PARAM_* constants.
     * @param int $maxLength [optional] A hint for pre-allocation.
     * @param mixed $driverOptions [optional] Optional parameter(s) for the driver.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function bindColumn(
            int|string $column,
            mixed &$var,
            int $type = PDO::PARAM_STR,
            int $maxLength = 0,
            mixed $driverOptions = null
        ): bool {}

    /**
     * Binds a value to a parameter
     * @param mixed $param Parameter identifier. For a prepared statement using named placeholders, this will be a parameter name of the form :name. For a prepared statement using question mark placeholders, this will be the 1-indexed position of the parameter.
     * @param mixed $value The value to bind to the parameter.
     * @param int $type [optional] Explicit data type for the parameter using the PDO::PARAM_* constants.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function bindValue(
            int|string $param,
            mixed $value,
            int $type = PDO::PARAM_STR
        ): bool {}

    /**
     * Returns the number of rows affected by the last SQL statement
     * @return int the number of rows.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function rowCount(): int {}

    /**
     * Returns a single column from the next row of a result set
     * @param int $column [optional] 0-indexed number of the column you wish to retrieve from the row. If no value is supplied, PDOStatement::fetchColumn fetches the first column.
     * @return mixed Returns a single column from the next row of a result set or FALSE if there are no more rows. There is no way to return another column from the same row if you use PDOStatement::fetchColumn to retrieve data.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function fetchColumn(int $column = 0): mixed {}

    /**
     * Returns an array containing all of the remaining rows in the result set.
     * The array represents each row as either an array of column values or an
     * object with properties corresponding to each column name.
     * An empty array is returned if there are zero results to fetch.
     *
     * Using this method to fetch large result sets will result in a heavy
     * demand on system and possibly network resources. Rather than retrieving
     * all of the data and manipulating it in PHP, consider using the database
     * server to manipulate the result sets. For example, use the WHERE and
     * ORDER BY clauses in SQL to restrict results before retrieving and
     * processing them with PHP.
     * @param int $mode [optional] Controls the contents of the returned array as documented in PDOStatement::fetch. Defaults to value of PDO::ATTR_DEFAULT_FETCH_MODE (which defaults to PDO::FETCH_BOTH) To return an array consisting of all values of a single column from the result set, specify ...
     * @param mixed ...$args Arguments of custom class constructor when the fetch_style parameter is PDO::FETCH_CLASS.
     * @return ($mode is PDO::FETCH_COLUMN ? list<mixed> : ($mode is PDO::FETCH_KEY_PAIR ? array<array-key, mixed> : ($mode is PDO::FETCH_ASSOC ? list<array<string, mixed>> : ($mode is PDO::FETCH_NUM ? list<list<mixed>> : ($mode is PDO::FETCH_BOTH ? list<array<string|int, mixed>> : ($mode is ...
     * @throws PDOException PDOStatement::fetchAll throws on failure if the attribute PDO::ATTR_ERRMODE is set to PDO::ERRMODE_EXCEPTION.
     */
    public function fetchAll(
            int $mode = PDO::FETCH_DEFAULT,
            mixed ...$args
        ): array {}

    /**
     * Fetches the next row and returns it as an object
     *
     * Fetches the next row and returns it as an object. This function is an alternative to
     * PDOStatement::fetch with PDO::FETCH_CLASS or PDO::FETCH_OBJ style.
     * @template T Fetches the next row and returns it as an object.
     * @param class-string<T> $class [optional] Name of the created class.
     * @param array $constructorArgs [optional] Elements of this array are passed to the constructor.
     * @return T|stdClass|false an instance of the required class with property names that correspond to the column names or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function fetchObject(
            string|null $class = "stdClass",
            array $constructorArgs = []
        ): object|false {}

    /**
     * Fetch the SQLSTATE associated with the last operation on the statement handle
     * @return string Identical to PDO::errorCode, except that PDOStatement::errorCode only retrieves error codes for operations performed with PDOStatement objects.
     */
    public function errorCode(): ?string {}

    /**
     * Fetch extended error information associated with the last operation on the statement handle
     * @return array PDOStatement::errorInfo returns an array of error information about the last operation performed by this statement handle. The array consists of the following fields: Element Information 0 SQLSTATE error code (a five characters alphanumeric identifier defined in the ANSI SQL ...
     */
    public function errorInfo(): array {}

    /**
     * Set a statement attribute
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
     * Retrieve a statement attribute
     * @param int $name The attribute to query.
     * @return mixed the attribute value.
     */
    public function getAttribute(int $name): mixed {}

    /**
     * Returns the number of columns in the result set
     * @return int the number of columns in the result set represented by the PDOStatement object. If there is no result set, PDOStatement::columnCount returns 0.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function columnCount(): int {}

    /**
     * Returns metadata for a column in a result set
     * @param int $column The 0-indexed column in the result set.
     * @return array|false an associative array containing the following values representing the metadata for a single column: Column metadata Name Value native_type The PHP native type used to represent the column value. driver:decl_type The SQL type used to represent the column value in the database. If ...
     */
    public function getColumnMeta(int $column): array|false {}

    /**
     * Set the default fetch mode for this statement
     * @param int $mode The fetch mode must be one of the PDO::FETCH_* constants.
     * @param mixed ...$args  Constructor arguments.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function setFetchMode(int $mode, mixed ...$args): bool {}

    /**
     * Advances to the next rowset in a multi-rowset statement handle
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function nextRowset(): bool {}

    /**
     * Closes the cursor, enabling the statement to be executed again.
     * @return bool TRUE on success or FALSE on failure.
     * @throws PDOException On error if PDO::ERRMODE_EXCEPTION option is true.
     */
    public function closeCursor(): bool {}

    /**
     * Dump an SQL prepared command
     * @return bool|null No value is returned.
     */
    public function debugDumpParams(): ?bool {}

    final public function __wakeup() {}

    final public function __sleep() {}

    /**
     * Gets result set iterator
     * @return Iterator
     * @since 8.0
     */
    public function getIterator(): Iterator {}

    public function connect() {}
}
