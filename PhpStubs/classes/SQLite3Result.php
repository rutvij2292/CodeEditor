<?php

/**
 * A class that handles result sets for the SQLite 3 extension.
 */
class SQLite3Result
{
    /**
     * Returns the number of columns in the result set
     * @return int the number of columns in the result set.
     */
    public function numColumns(): int {}

    /**
     * Returns the name of the nth column
     * @param int $column The numeric zero-based index of the column.
     * @return string|false the string name of the column identified by column_number.
     */
    public function columnName(int $column): string|false {}

    /**
     * Returns the type of the nth column
     * @param int $column The numeric zero-based index of the column.
     * @return int|false the data type index of the column identified by column_number (one of SQLITE3_INTEGER, SQLITE3_FLOAT, SQLITE3_TEXT, SQLITE3_BLOB, or SQLITE3_NULL).
     */
    public function columnType(int $column): int|false {}

    /**
     * Fetches a result row as an associative or numerically indexed array or both
     * @param int $mode [optional] Controls how the next row will be returned to the caller. This value must be one of either SQLITE3_ASSOC, SQLITE3_NUM, or SQLITE3_BOTH. SQLITE3_ASSOC: returns an array indexed by column name as returned in the corresponding result set
     * @return array|false a result row as an associatively or numerically indexed array or both. Alternately will return FALSE if there are no more rows.
     */
    public function fetchArray(int $mode = SQLITE3_BOTH): array|false {}

    /**
     * Resets the result set back to the first row
     * @return bool TRUE if the result set is successfully reset back to the first row, FALSE on failure.
     */
    public function reset(): bool {}

    /**
     * Closes the result set
     * @return bool TRUE.
     * @throws \Error An Error is thrown if the method is called on an uninitialized object.
     */
    public function finalize(): bool {}

    /**
     * Constructs an SQLite3Result
     *
     * SQLite3Result instances are created by SQLite3::query and SQLite3Stmt::execute.
     */
    private function __construct() {}

    /**
     * @since 8.5
     */
    public function fetchAll(int $mode = 3): array|false {}
}
