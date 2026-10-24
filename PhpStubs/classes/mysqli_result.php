<?php

/**
 * Represents the result set obtained from a query against the database.
 * Implements Traversable since 5.4
 */
class mysqli_result implements IteratorAggregate
{
    /**
     * @var int
     */
    public int $current_field;

    /**
     * @var int
     */
    public int $field_count;

    /**
     * @var array|null
     */
    public array|null $lengths;

    /**
     * @var int
     */
    public int|string $num_rows;

    /**
     * @var mixed
     */
    public int $type;

    /**
     * Constructor (no docs available)
     * @param object $mysql Procedural style only: A mysqli object returned by mysqli_connect or mysqli_init
     * @param int $result_mode [optional]
     * @throws \mysqli_sql_exception If mysqli error reporting is enabled (MYSQLI_REPORT_ERROR) and the requested operation fails, a warning is generated. If, in addition, the mode is set to MYSQLI_REPORT_STRICT, a mysqli_sql_exception is thrown instead.
     */
    public function __construct(
        mysqli $mysql,
        int $result_mode = MYSQLI_STORE_RESULT
    ) {}

    /**
     * Frees the memory associated with a result
     * @return void No value is returned.
     */
    public function close(): void {}

    /**
     * Frees the memory associated with a result
     * @return void No value is returned.
     */
    public function free(): void {}

    /**
     * Adjusts the result pointer to an arbitrary row in the result
     * @param int $offset The field offset. Must be between zero and the total number of rows minus one (0..mysqli_num_rows - 1).
     * @return bool true on success or false on failure.
     */
    public function data_seek(int $offset): bool {}

    /**
     * Returns the next field in the result set
     * @return object|false an object which contains field definition information or false if no field information is available. Object properties Property Description name The name of the column orgname Original column name if an alias was specified table The name of the table this field belongs to (if ...
     */
    public function fetch_field(): object|false {}

    /**
     * Returns an array of objects representing the fields in a result set
     * @return array an array of objects containing field definition information. Object properties Property Description name The name of the column orgname Original column name if an alias was specified table The name of the table this field belongs to (if not calculated) orgtable Original table name if ...
     */
    public function fetch_fields(): array {}

    /**
     * Fetch meta-data for a single field
     * @param int $index The field number. This value must be in the range from 0 to number of fields - 1.
     * @return object|false an object which contains field definition information or false if no field information for specified fieldnr is available. Object attributes Attribute Description name The name of the column orgname Original column name if an alias was specified table The name of the table this ...
     */
    public function fetch_field_direct(int $index): object|false {}

    /**
     * Fetches all result rows as an associative array, a numeric array, or both
     * @param int $mode [optional] This optional parameter is a constant indicating what type of array should be produced from the current row data. The possible values for this parameter are the constants MYSQLI_ASSOC, MYSQLI_NUM, or MYSQLI_BOTH.
     * @return array an array of associative or numeric arrays holding result rows.
     */
    public function fetch_all(int $mode = MYSQLI_NUM): array {}

    /**
     * Fetch the next row of a result set as an associative, a numeric array, or both
     * @param int $mode [optional] This optional parameter is a constant indicating what type of array should be produced from the current row data. The possible values for this parameter are the constants MYSQLI_ASSOC, MYSQLI_NUM, or MYSQLI_BOTH. By using the MYSQLI_ASSOC constant this function will ...
     * @return array|false|null an array representing the fetched row, null if there are no more rows in the result set, or false on failure.
     */
    public function fetch_array(int $mode = MYSQLI_BOTH): array|false|null {}

    /**
     * Fetch the next row of a result set as an associative array
     * @return array|false|null an associative array representing the fetched row, where each key in the array represents the name of one of the result set's columns, null if there are no more rows in the result set, or false on failure.
     */
    public function fetch_assoc(): array|false|null {}

    /**
     * Fetch the next row of a result set as an object
     *
     * Fetches one row of data from the result set and returns it as an object, where each property
     * represents the name of the result set's column. Each subsequent call to this function will
     * return the next row within the result set, or null if there are no more rows.
     * @template T of object Fetch the next row of a result set as an object
     * @param class-string<T> $class [optional] The name of the class to instantiate, set the properties of and return. If not specified, a stdClass object is returned.
     * @param null|array $constructor_args [optional] An optional array of parameters to pass to the constructor for class_name objects.
     * @return T|stdClass|false|null an object representing the fetched row, where each property represents the name of the result set's column, null if there are no more rows in the result set, or false on failure.
     */
    public function fetch_object(string $class = 'stdClass', array $constructor_args = []): object|false|null {}

    /**
     * Fetch the next row of a result set as an enumerated array
     * @return array|false|null an enumerated array representing the fetched row, null if there are no more rows in the result set, or false on failure.
     */
    public function fetch_row(): array|false|null {}

    /**
     * Fetch a single column from the next row of a result set
     * @param int $column [optional] 0-indexed number of the column you wish to retrieve from the row. If no value is supplied, the first column will be returned.
     * @return string|int|float|false|null a single column from the next row of a result set or false if there are no more rows.
     */
    public function fetch_column(int $column = 0): string|int|float|false|null {}

    /**
     * Set result pointer to a specified field offset
     * @param int $index The field number. This value must be in the range from 0 to number of fields - 1.
     */
    public function field_seek(int $index): true {}

    /**
     * Frees the memory associated with a result
     * @return void No value is returned.
     */
    public function free_result(): void {}

    /**
     * Retrieve an external iterator
     * @return Iterator
     * @since 8.0
     */
    public function getIterator(): Iterator {}
}
