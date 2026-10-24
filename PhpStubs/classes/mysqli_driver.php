<?php

/**
 * MySQLi Driver.
 */
final class mysqli_driver
{
    /**
     * @var string
     */
    public string $client_info;

    /**
     * @var int
     */
    public int $client_version;

    /**
     * @var int
     */
    public int $driver_version;

    /**
     * @var string
     */
    public $embedded;

    /**
     * @var bool
     */
    public bool $reconnect;

    /**
     * @var int
     */
    public int $report_mode;
}
