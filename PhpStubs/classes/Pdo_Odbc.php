<?php
namespace Pdo;

use PDO;

/**
 * A PDO subclass representing a connection using the ODBC PDO driver.
 * @since 8.4
 */
class Odbc extends PDO
{
    public const int ATTR_USE_CURSOR_LIBRARY = 1000;

    public const int ATTR_ASSUME_UTF8 = 1001;

    public const int SQL_USE_IF_NEEDED = 0;

    public const int SQL_USE_ODBC = 1;

    public const int SQL_USE_DRIVER = 2;
}
