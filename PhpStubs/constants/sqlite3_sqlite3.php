<?php

/**
 * Specifies that the Sqlite3Result::fetchArray
 * method shall return an array indexed by column name as returned in the
 * corresponding result set.
 */
const SQLITE3_ASSOC = 1;

/**
 * Specifies that the Sqlite3Result::fetchArray
 * method shall return an array indexed by column number as returned in the
 * corresponding result set, starting at column 0.
 */
const SQLITE3_NUM = 2;

/**
 * Specifies that the Sqlite3Result::fetchArray
 * method shall return an array indexed by both column name and number as
 * returned in the corresponding result set, starting at column 0.
 */
const SQLITE3_BOTH = 3;

/**
 * Represents the SQLite3 INTEGER storage class.
 */
const SQLITE3_INTEGER = 1;

/**
 * Represents the SQLite3 REAL (FLOAT) storage class.
 */
const SQLITE3_FLOAT = 2;

/**
 * Represents the SQLite3 TEXT storage class.
 */
const SQLITE3_TEXT = 3;

/**
 * Represents the SQLite3 BLOB storage class.
 */
const SQLITE3_BLOB = 4;

/**
 * Represents the SQLite3 NULL storage class.
 */
const SQLITE3_NULL = 5;

/**
 * Specifies that the SQLite3 database be opened for reading only.
 */
const SQLITE3_OPEN_READONLY = 1;

/**
 * Specifies that the SQLite3 database be opened for reading and writing.
 */
const SQLITE3_OPEN_READWRITE = 2;

/**
 * Specifies that the SQLite3 database be created if it does not already
 * exist.
 */
const SQLITE3_OPEN_CREATE = 4;

/**
 * Specifies that a function created with SQLite3::createFunction() is deterministic,
 * i.e. it always returns the same result given the same inputs within a single SQL statement.
 * @since 7.1.4
 */
const SQLITE3_DETERMINISTIC = 2048;
