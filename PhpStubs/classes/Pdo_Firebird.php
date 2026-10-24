<?php
namespace Pdo;

use PDO;

/**
 * A PDO subclass representing a connection using the Firebird PDO driver.
 * @since 8.4
 */
class Firebird extends PDO
{
    public const int ATTR_DATE_FORMAT = 1000;

    public const int ATTR_TIME_FORMAT = 1001;

    public const int ATTR_TIMESTAMP_FORMAT = 1002;

    public const int TRANSACTION_ISOLATION_LEVEL = 1003;

    public const int READ_COMMITTED = 1004;

    public const int REPEATABLE_READ = 1005;

    public const int SERIALIZABLE = 1006;

    public const int WRITABLE_TRANSACTION = 1007;

    /**
     * Get the API version
     *
     * Returns the Firebird API version as defined by the C constant FB_API_VER in ibase.h.
     * @return int Returns the FireBird API as an int.
     */
    public static function getApiVersion(): int {}
}
