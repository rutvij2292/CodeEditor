<?php
namespace Pdo;

use PDO;

/**
 * A PDO subclass representing a connection using the DBLib PDO driver.
 * @since 8.4
 */
class Dblib extends PDO
{
    public const int ATTR_CONNECTION_TIMEOUT = 1000;

    public const int ATTR_QUERY_TIMEOUT = 1001;

    public const int ATTR_STRINGIFY_UNIQUEIDENTIFIER = 1002;

    public const int ATTR_VERSION = 1003;

    public const int ATTR_TDS_VERSION = 1004;

    public const int ATTR_SKIP_EMPTY_ROWSETS = 1005;

    public const int ATTR_DATETIME_CONVERT = 1006;
}
