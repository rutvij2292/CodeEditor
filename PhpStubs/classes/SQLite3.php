<?php

/**
 * A class that interfaces SQLite 3 databases.
 */
class SQLite3
{
    /**
     * @since 8.0
     */
    public const OK = 0;

    /**
     * @since 8.0
     */
    public const DENY = 1;

    /**
     * @since 8.0
     */
    public const IGNORE = 2;

    /**
     * @since 8.0
     */
    public const CREATE_INDEX = 1;

    /**
     * @since 8.0
     */
    public const CREATE_TABLE = 2;

    /**
     * @since 8.0
     */
    public const CREATE_TEMP_INDEX = 3;

    /**
     * @since 8.0
     */
    public const CREATE_TEMP_TABLE = 4;

    /**
     * @since 8.0
     */
    public const CREATE_TEMP_TRIGGER = 5;

    /**
     * @since 8.0
     */
    public const CREATE_TEMP_VIEW = 6;

    /**
     * @since 8.0
     */
    public const CREATE_TRIGGER = 7;

    /**
     * @since 8.0
     */
    public const CREATE_VIEW = 8;

    /**
     * @since 8.0
     */
    public const DELETE = 9;

    /**
     * @since 8.0
     */
    public const DROP_INDEX = 10;

    /**
     * @since 8.0
     */
    public const DROP_TABLE = 11;

    /**
     * @since 8.0
     */
    public const DROP_TEMP_INDEX = 12;

    /**
     * @since 8.0
     */
    public const DROP_TEMP_TABLE = 13;

    /**
     * @since 8.0
     */
    public const DROP_TEMP_TRIGGER = 14;

    /**
     * @since 8.0
     */
    public const DROP_TEMP_VIEW = 15;

    /**
     * @since 8.0
     */
    public const DROP_TRIGGER = 16;

    /**
     * @since 8.0
     */
    public const DROP_VIEW = 17;

    /**
     * @since 8.0
     */
    public const INSERT = 18;

    /**
     * @since 8.0
     */
    public const PRAGMA = 19;

    /**
     * @since 8.0
     */
    public const READ = 20;

    /**
     * @since 8.0
     */
    public const SELECT = 21;

    /**
     * @since 8.0
     */
    public const TRANSACTION = 22;

    /**
     * @since 8.0
     */
    public const UPDATE = 23;

    /**
     * @since 8.0
     */
    public const ATTACH = 24;

    /**
     * @since 8.0
     */
    public const DETACH = 25;

    /**
     * @since 8.0
     */
    public const ALTER_TABLE = 26;

    /**
     * @since 8.0
     */
    public const REINDEX = 27;

    /**
     * @since 8.0
     */
    public const ANALYZE = 28;

    /**
     * @since 8.0
     */
    public const CREATE_VTABLE = 29;

    /**
     * @since 8.0
     */
    public const DROP_VTABLE = 30;

    /**
     * @since 8.0
     */
    public const FUNCTION = 31;

    /** @since 8.0 */
    public const SAVEPOINT = 32;

    /** @since 8.0 */
    public const COPY = 0;

    /** @since 8.0 */
    public const RECURSIVE = 33;

    /**
     * Opens an SQLite database
     * @link https://php.net/manual/en/sqlite3.open.php
     * @param string $filename <p>
     * Path to the SQLite database, or :memory: to use in-memory database.
     * </p>
     * @param int $flags <p>
     * Optional flags used to determine how to open the SQLite database. By
     * default, open uses SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE.
     * </p>
     * <p>
     * SQLITE3_OPEN_READONLY: Open the database for
     * reading only.
     * </p>
     * @param string $encryptionKey <p>
     * An optional encryption key used when encrypting and decrypting an
     * SQLite database.
     * </p>
     * @return void No value is returned.
     */
    #[TentativeType]
    public function open(
        string $filename,
        int $flags = SQLITE3_OPEN_READWRITE|SQLITE3_OPEN_CREATE,
        string 

    /**
     * @since 8.0
     */
    public const SAVEPOINT = 32;

    /**
     * @since 8.0
     */
    public const COPY = 0;

    /**
     * @since 8.0
     */
    public const RECURSIVE = 33;

    /**
     * Opens an SQLite database
     * @param string $filename Path to the SQLite database, or :memory: to use in-memory database.
     * @param int $flags Optional flags used to determine how to open the SQLite database. By default, open uses SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE. SQLITE3_OPEN_READONLY: Open the database for reading only.
     * @param string $encryptionKey An optional encryption key used when encrypting and decrypting an SQLite database.
     * @return void No value is returned.
     */
    public function open(
        string $filename,
        int $flags = SQLITE3_OPEN_READWRITE|SQLITE3_OPEN_CREATE,
        string $encryptionKey = ''
    ): void {}

    /**
     * Closes the database connection
     * @return bool TRUE on success, FALSE on failure.
     */
    public function close(): bool {}

    /**
     * Executes a result-less query against a given database
     * @param string $query The SQL query to execute (typically an INSERT, UPDATE, or DELETE query).
     * @return bool TRUE if the query succeeded, FALSE on failure.
     */
    public function exec(string $query): bool {}

    /**
     * Returns the SQLite3 library version as a string constant and as a number
     * @return array an associative array with the keys "versionString" and "versionNumber".
     */
    public static function version(): array {}

    /**
     * Returns the row ID of the most recent INSERT into the database
     * @return int the row ID of the most recent INSERT into the database
     */
    public function lastInsertRowID(): int {}

    /**
     * Returns the numeric result code of the most recent failed SQLite request
     * @return int an integer value representing the numeric result code of the most recent failed SQLite request.
     */
    public function lastErrorCode(): int {}

    /**
     * Returns English text describing the most recent failed SQLite request
     * @return string an English string describing the most recent failed SQLite request.
     */
    public function lastErrorMsg(): string {}

    /**
     * Sets the busy connection handler
     * @param int $milliseconds The milliseconds to sleep. Setting this value to a value less than or equal to zero, will turn off an already set timeout handler.
     * @return bool TRUE on success, FALSE on failure.
     * @since 5.3
     */
    public function busyTimeout(int $milliseconds): bool {}

    /**
     * Attempts to load an SQLite extension library
     * @param string $name The name of the library to load. The library must be located in the directory specified in the configure option sqlite3.extension_dir.
     * @return bool TRUE if the extension is successfully loaded, FALSE on failure.
     */
    public function loadExtension(string $name): bool {}

    /**
     * Returns the number of database rows that were changed (or inserted or
     * deleted) by the most recent SQL statement
     * @return int an integer value corresponding to the number of database rows changed (or inserted or deleted) by the most recent SQL statement.
     */
    public function changes(): int {}

    /**
     * Returns a string that has been properly escaped
     * @param string $string The string to be escaped.
     * @return string a properly escaped string that may be used safely in an SQL statement.
     */
    public static function escapeString(string $string): string {}

    /**
     * Prepares an SQL statement for execution
     * @param string $query The SQL query to prepare.
     * @return SQLite3Stmt|false an SQLite3Stmt object on success or FALSE on failure.
     */
    public function prepare(string $query): SQLite3Stmt|false {}

    /**
     * Executes an SQL query
     * @param string $query The SQL query to execute.
     * @return SQLite3Result|false an SQLite3Result object, or FALSE on failure.
     */
    public function query(string $query): SQLite3Result|false {}

    /**
     * Executes a query and returns a single result
     * @param string $query The SQL query to execute.
     * @param bool $entireRow [optional] By default, querySingle returns the value of the first column returned by the query. If entire_row is TRUE, then it returns an array of the entire first row.
     * @return mixed the value of the first column of results or an array of the entire first row (if entire_row is TRUE). If the query is valid but no results are returned, then NULL will be returned if entire_row is FALSE, otherwise an empty array is returned. Invalid or failing queries will return ...
     */
    public function querySingle(
        string $query,
        bool $entireRow = false
    ): mixed {}

    /**
     * Registers a PHP function for use as an SQL scalar function
     * @param string $name Name of the SQL function to be created or redefined.
     * @param mixed $callback The name of a PHP function or user-defined function to apply as a callback, defining the behavior of the SQL function.
     * @param int $argCount The number of arguments that the SQL function takes. If this parameter is negative, then the SQL function may take any number of arguments.
     * @param int $flags A bitwise conjunction of flags. Currently, only SQLITE3_DETERMINISTIC is supported, which specifies that the function always returns the same result given the same inputs within a single SQL statement.
     * @return bool TRUE upon successful creation of the function, FALSE on failure.
     */
    public function createFunction(
        string $name,
        callable $callback,
        int $argCount = -1,
        int $flags = 0
    ): bool {}

    /**
     * Registers a PHP function for use as an SQL aggregate function
     * @param string $name Name of the SQL aggregate to be created or redefined.
     * @param mixed $stepCallback The name of a PHP function or user-defined function to apply as a callback for every item in the aggregate.
     * @param mixed $finalCallback The name of a PHP function or user-defined function to apply as a callback at the end of the aggregate data.
     * @param int $argCount [optional] The number of arguments that the SQL aggregate takes. If this parameter is negative, then the SQL aggregate may take any number of arguments.
     * @return bool TRUE upon successful creation of the aggregate, FALSE on failure.
     */
    public function createAggregate(
        string $name,
        callable $stepCallback,
        callable $finalCallback,
        int $argCount = -1
    ): bool {}

    /**
     * Registers a PHP function for use as an SQL collating function
     * @param string $name Name of the SQL collating function to be created or redefined
     * @param callable $callback The name of a PHP function or user-defined function to apply as a callback, defining the behavior of the collation. It should accept two strings and return as strcmp does, i.e. it should return -1, 1, or 0 if the first string sorts before, sorts after, or is equal to the ...
     * @return bool TRUE on success or FALSE on failure.
     * @since 5.3
     */
    public function createCollation(string $name, callable $callback): bool {}

    /**
     * Opens a stream resource to read a BLOB
     * @param string $table The table name.
     * @param string $column The column name.
     * @param int $rowid The row ID.
     * @param string $database [optional] The symbolic name of the DB
     * @param int $flags [optional] Either SQLITE3_OPEN_READONLY or SQLITE3_OPEN_READWRITE to open the stream for reading only, or for reading and writing, respectively.
     * @return resource|false Returns a stream resource, or FALSE on failure.
     */
    public function openBlob(
        string $table,
        string $column,
        int $rowid,
        string $database = 'main',
        int $flags = SQLITE3_OPEN_READONLY
    ) {}

    /**
     * Enable throwing exceptions
     * @param bool $enable When true, the SQLite3 instance, and SQLite3Stmt and SQLite3Result instances derived from it, will throw exceptions on error. When false, the SQLite3 instance, and SQLite3Stmt and SQLite3Result instances derived from it, will raise warnings on error. For either mode, the error ...
     * @return bool Returns the old value; true if exceptions were enabled, false otherwise.
     */
    public function enableExceptions(
        bool $enable = false
    ): bool {}

    /**
     * Instantiates an SQLite3 object and opens an SQLite 3 database
     * @param string $filename Path to the SQLite database, or :memory: to use in-memory database.
     * @param int $flags Optional flags used to determine how to open the SQLite database. By default, open uses SQLITE3_OPEN_READWRITE | SQLITE3_OPEN_CREATE. SQLITE3_OPEN_READONLY: Open the database for reading only.
     * @param string $encryptionKey An optional encryption key used when encrypting and decrypting an SQLite database.
     * @throws \Exception Throws an Exception on failure.
     */
    public function __construct(
        string $filename,
        int $flags = SQLITE3_OPEN_READWRITE|SQLITE3_OPEN_CREATE,
        string $encryptionKey = ''
    ) {}

    /**
     * @return int
     * @since 7.4
     */
    public function lastExtendedErrorCode(): int {}

    /**
     * @param bool $enable
     * @since 7.4
     */
    public function enableExtendedResultCodes(
        bool $enable = true
    ): bool {}

    /**
     * Backup one database to another database
     *
     * SQLite3::backup copies the contents of one database into another, overwriting the contents of
     * the destination database. It is useful either for creating backups of databases or for
     * copying in-memory databases to or from persistent files.
     * @param SQLite3 $destination A database connection opened with SQLite3::open.
     * @param string $sourceDatabase The database name is "main" for the main database, "temp" for the temporary database, or the name specified after the AS keyword in an ATTACH statement for an attached database.
     * @param string $destinationDatabase Analogous to sourceDatabase but for the destination.
     * @return bool Returns true on success or false on failure.
     * @since 7.4
     */
    public function backup(SQLite3 $destination, string $sourceDatabase = 'main', string $destinationDatabase = 'main'): bool {}

    /**
     * Configures a callback to be used as an authorizer to limit what a statement can do
     *
     * Sets a callback that will be called by SQLite every time an action is performed (reading,
     * deleting, updating, etc.). This is used when preparing a SQL statement from an untrusted
     * source to ensure that the SQL statements do not try to access data they are not allowed to
     * see, or that they do not try to execute malicious statements that damage the database. For
     * example, an application may allow a user to enter arbitrary SQL queries for evaluation by a
     * database. But the application does not want the user to be able to make arbitrary changes to
     * the database. An authorizer could then be put in place while the ...
     * @param null|callable $callback The callable to be called. If null is passed instead, this will disable the current authorizer callback.
     * @return bool Returns true on success or false on failure.
     * @since 8.0
     */
    public function setAuthorizer(?callable $callback): bool {}
}
