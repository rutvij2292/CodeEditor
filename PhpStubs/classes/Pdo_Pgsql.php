<?php
namespace Pdo;

use PDO;

/**
 * A PDO subclass representing a connection using the PostgreSQL PDO driver.
 *
 * This driver supports a dedicated SQL query parser for the PostgreSQL dialect. It can handle
 * the following: Single and double-quoted literals, with doubling as escaping mechanism C-style
 * “escape” string literals Dollar-quoted string literals Two-dashes and C-style comments
 * (non-nested). Support for ?? as escape sequence for the ? operator.
 * @since 8.4
 */
class Pgsql extends PDO
{
    public const int ATTR_DISABLE_PREPARES = 1000;

    public const int ATTR_RESULT_MEMORY_SIZE = 1001;

    public const int TRANSACTION_IDLE = 0;

    public const int TRANSACTION_ACTIVE = 1;

    public const int TRANSACTION_INTRANS = 2;

    public const int TRANSACTION_INERROR = 3;

    public const int TRANSACTION_UNKNOWN = 4;

    /**
     * Copy data from a PHP array into a table
     *
     * Copies data from rows array to table tableName using separator as fields delimiter and
     * fields list.
     * @param string $tableName String containing table name.
     * @param array $rows An indexed array (or Traversable) of strings with fields separated by separator.
     * @param string $separator Delimiter used to separate fields in an entry of the rows array.
     * @param string $nullAs How to interpret SQL NULL values.
     * @param string|null $fields List of fields to insert.
     * @return bool Returns true on success or false on failure.
     */
    public function copyFromArray(
            string $tableName,
            array $rows,
            string $separator = "\t",
            string $nullAs = "\\\\N",
            ?string $fields = null
        ): bool {}

    /**
     * Copy data from file into table
     *
     * Copies data from file specified by filename into table tableName using separator as
     * fields delimiter and fields list
     * @param string $tableName String containing table name.
     * @param string $filename Filename containing the data to import.
     * @param string $separator Delimiter used to separate fields in an entry of the rows array.
     * @param string $nullAs How to interpret SQL NULL values.
     * @param string|null $fields List of fields to insert.
     * @return bool Returns true on success or false on failure.
     * @throws \PDOException If filename cannot be opened for reading, the failure is reported through the connection's error handling (see PDO::ATTR_ERRMODE); with PDO::ERRMODE_EXCEPTION a PDOException is thrown.
     */
    public function copyFromFile(
            string $tableName,
            string $filename,
            string $separator = "\t",
            string $nullAs = "\\\\N",
            ?string $fields = null
        ): bool {}

    /**
     * Copy data from database table into PHP array
     *
     * Copies data from tableName into array using separator as fields delimiter and fields list
     * @param string $tableName String containing table name.
     * @param string $separator Delimiter used to separate fields in an entry of the rows array.
     * @param string $nullAs How to interpret SQL NULL values.
     * @param string|null $fields List of fields to export.
     * @return array|false Returns an array of rows, or false on failure.
     */
    public function copyToArray(
            string $tableName,
            string $separator = "\t",
            string $nullAs = "\\\\N",
            ?string $fields = null
        ): array|false {}

    /**
     * Copy data from table into file
     *
     * Copies data from table into file specified by filename using separator as fields
     * delimiter and fields list.
     * @param string $tableName String containing table name.
     * @param string $filename Filename to export data.
     * @param string $separator Delimiter used to separate fields in an entry of the rows array.
     * @param string $nullAs How to interpret SQL NULL values.
     * @param string|null $fields List of fields to export.
     * @return bool Returns true on success or false on failure.
     * @throws \PDOException If filename cannot be opened for writing, or cannot be written to, the failure is reported through the connection's error handling (see PDO::ATTR_ERRMODE); with PDO::ERRMODE_EXCEPTION a PDOException is thrown.
     */
    public function copyToFile(
            string $tableName,
            string $filename,
            string $separator = "\t",
            string $nullAs = "\\\\N",
            ?string $fields = null
        ): bool {}

    /**
     * Escapes a string for use as an SQL identifier
     *
     * Escapes a string for use as an SQL identifier, such as a table, column, or function name.
     * This is useful when a user-supplied identifier might contain special characters that
     * would otherwise not be interpreted as part of the identifier by the SQL parser, or when
     * the identifier might contain upper case characters whose case should be preserved.
     * @param string $input A string containing text to be escaped.
     * @return string A string containing the escaped data.
     */
    public function escapeIdentifier(string $input): string {}

    /**
     * Get asynchronous notification
     *
     * Returns a result set representing a pending asynchronous notification.
     * @param int $fetchMode The format the result set should be returned as, one of the following constants: PDO::FETCH_DEFAULT PDO::FETCH_BOTH PDO::FETCH_ASSOC PDO::FETCH_NUM
     * @param int $timeoutMilliseconds The length of time to wait for a response, in milliseconds.
     * @return array|false If a notification is pending, returns a single row, otherwise returns false. The row has a message field (the channel name) and a pid field (the process ID of the notifying backend). If the notification carries a non-empty payload, the row also has a payload field. With ...
     * @throws \ValueError A ValueError is thrown if fetchMode is not one of the valid PDO::FETCH_* constants. A ValueError is thrown if timeoutMilliseconds is less than 0. A E_WARNING is raised when timeoutMilliseconds is greater than the value that can be contained in a signed 32-bit integer, in which ...
     */
    public function getNotify(int $fetchMode = \PDO::FETCH_DEFAULT, int $timeoutMilliseconds = 0): array|false {}

    /**
     * Get the PID of the backend process handling this connection
     *
     * Returns the PID of the backend process handling this connection. Note that the PID
     * belongs to a process executing on the database server host, not the local host.
     * @return int Returns the PID as an int.
     */
    public function getPid(): int {}

    /**
     * Creates a new large object
     *
     * Pdo\Pgsql::lobCreate creates a large object and returns the OID which refers to it. It
     * can be opened to read or write data with Pdo\Pgsql::lobOpen.
     * @return string|false Returns the OID of the newly created large object on success, or false on failure.
     */
    public function lobCreate(): string|false {}

    /**
     * Opens an existing large object stream. Must be called inside a transaction.
     * @return resource|false Returns a stream resource on success, or false on failure.
     */
    public function lobOpen(string $oid, string $mode = "rb") {}

    /**
     * Deletes the large object
     *
     * Pdo\Pgsql::lobCreate creates a large object and returns the OID which refers to it. It
     * can be opened to read or write data with Pdo\Pgsql::lobOpen. Deletes a large object from
     * the database identified by OID.
     * @param string $oid A large object identifier.
     * @return bool Returns true on success or false on failure.
     */
    public function lobUnlink(string $oid): bool {}

    /**
     * Set a callback to handle notice and warning messages generated by the backend
     *
     * Set a callback to handle notice and warning messages generated by the backend. This
     * includes messages emitted by PostgreSQL itself, as well as those raised by user-defined
     * SQL functions using RAISE. Please note that the actual receipt of these messages depends
     * on the backend setting client_min_messages.
     * @param callable|null $callback If null is passed, the handler is reset to its default state. Otherwise, the handler is a callback with the following signature: voidhandler stringmessage message A message generated by the backend.
     * @return void No value is returned.
     */
    public function setNoticeCallback(?callable $callback): void {}
}
