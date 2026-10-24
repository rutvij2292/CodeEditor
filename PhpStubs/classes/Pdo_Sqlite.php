<?php
namespace Pdo;

use PDO;

/**
 * A PDO subclass representing a connection using the SQLite PDO driver.
 *
 * This driver supports a dedicated SQL query parser for the SQLite dialect. It can handle the
 * following: Single, double-quoted, and backtick literals, with doubling as escaping mechanism.
 * Square brackets quoting for identifiers. Two-dashes and C-style comments (non-nested).
 * @since 8.4
 */
class Sqlite extends PDO
{
    public const int DETERMINISTIC = 2048;

    public const int OPEN_READONLY = 1;

    public const int OPEN_READWRITE = 2;

    public const int OPEN_CREATE = 4;

    public const int ATTR_OPEN_FLAGS = 1000;

    public const int ATTR_READONLY_STATEMENT = 1001;

    public const int ATTR_EXTENDED_RESULT_CODES = 1002;

    /**
     * @since 8.5
     */
    public const IGNORE = 2;

    /**
     * @since 8.5
     */
    public const DENY = 1;

    /**
     * @since 8.5
     */
    public const OK = 0;

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
     * @since 8.5
     */
    public const ATTR_EXPLAIN_STATEMENT = 1004;

    /**
     * @since 8.5
     */
    public const ATTR_BUSY_STATEMENT = 1003;

    /**
     * @since 8.5
     */
    public const ATTR_TRANSACTION_MODE = 1005;

    /**
     * @since 8.5
     */
    public const TRANSACTION_MODE_DEFERRED = 0;

    /**
     * @since 8.5
     */
    public const TRANSACTION_MODE_IMMEDIATE = 1;

    /**
     * @since 8.5
     */
    public const TRANSACTION_MODE_EXCLUSIVE = 2;

    /**
     * Registers an aggregating user-defined function for use in SQL statements
     *
     * This method is similar to Pdo\Sqlite::createFunction except that it registers functions
     * that can be used to calculate a result aggregated across all the rows of a query.
     * @param string $name The name of the function used in SQL statements.
     * @param callable $step Callback function called for each row of the result set. The callback should accumulate the result and store it in the aggregation context. This function need to be defined as: step ( mixed \$context , int \$rownumber , mixed \$value , mixed \$values ): mixed \$context - null ...
     * @param callable $finalize Callback function to aggregate the "stepped" data from each row. Once all the rows have been processed, this function will be called, and it should then take the data from the aggregation context and return the result. This callback function should return a type understood ...
     * @param int $numArgs Hint to the SQLite parser if the callback function accepts a predetermined number of arguments.
     * @return bool Returns true on success or false on failure.
     */
    public function createAggregate(
            string $name,
            callable $step,
            callable $finalize,
            int $numArgs = -1
        ): bool {}

    /**
     * Registers a user-defined function for use as a collating function in SQL statements
     *
     * This method is similar to Pdo\Sqlite::createFunction except that it registers functions
     * that are used to collate strings.
     * @param string $name Name of the SQL collating function to be created or redefined.
     * @param callable $callback Callback function that defines the behaviour of a collation. It must accept two strings and return -1, 0, or 1 if the first string sorts before, sorts identically, or sorts after the second string respectively. An internal function that behaves like this is strcmp. This ...
     * @return bool Returns true on success or false on failure.
     */
    public function createCollation(string $name, callable $callback): bool {}

    /**
     * Registers a user-defined function for use in SQL statements
     *
     * This method allows PHP function to be registered with SQLite as a user-defined function,
     * so that it can be called within SQL queries. The defined function can be used in any SQL
     * query that allows function calls, for example SELECT, UPDATE, or triggers.
     * @param string $function_name The name of the function used in SQL statements.
     * @param callable $callback Callback function to handle the defined SQL function. Callback functions should return a type understood by SQLite (i.e. scalar type). This function need to be defined as: callback ( mixed \$value , mixed \$values ): mixed \$value - The first argument passed to the SQL ...
     * @param int $num_args The number of arguments that the SQL function takes. If this parameter is -1, then the SQL function may take any number of arguments.
     * @param int $flags A bitmask of flags. Currently, only Pdo\Sqlite::DETERMINISTIC is supported, which specifies that the function always returns the same result given the same inputs within a single SQL statement.
     * @return bool Returns true on success or false on failure.
     */
    public function createFunction(
            string $function_name,
            callable $callback,
            int $num_args = -1,
            int $flags = 0
        ): bool {}

    /**
     * Description
     * @param string $name Description.
     * @return void No value is returned.
     * @throws \Exception When does this function issue E_* level errors, and/or throw Exceptions.
     */
    public function loadExtension(string $name): void {}

    /**
     * Description
     * @return resource|false
     * @throws \Exception When does this function issue E_* level errors, and/or throw Exceptions.
     */
    public function openBlob(
            string $table,
            string $column,
            int $rowid,
            ?string $dbname = "main",
            int $flags = \Pdo\Sqlite::OPEN_READONLY
        ) {}

    /**
     * @since 8.5
     */
    public function setAuthorizer(?callable $callback): void {}
}
