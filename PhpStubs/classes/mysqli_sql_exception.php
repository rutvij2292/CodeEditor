<?php

/**
 * mysqli_sql_exception
 */
final class mysqli_sql_exception extends RuntimeException
{
    /**
     * The sql state with the error.
     * @var string
     */
    protected string $sqlstate;

    /**
     * The error code
     * @var int
     */
    protected $code;

    /**
     * Returns the SQLSTATE error code
     *
     * Returns a string containing the SQLSTATE error code for the last error. The error code
     * consists of five characters. The values are specified by ANSI SQL and ODBC. For a list of
     * possible values, see .
     * @since 8.1
     */
    public function getSqlState(): string {}
}
