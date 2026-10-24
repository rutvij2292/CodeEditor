<?php

/**
 * Represents a row from a result set returned by PDOStatement::fetch called with
 * PDO::FETCH_LAZY fetch mode.
 *
 * Objects of this class cannot be instantiated and are not serializable. The PDORow object
 * allows access to the returned data as if both PDO::FETCH_OBJ and PDO::FETCH_BOTH mode were
 * used. This means that the returned data can be accessed as object properties, and as an array
 * both indexed by the column name and a column offset number.
 */
final class PDORow
{
    public string $queryString;
}
