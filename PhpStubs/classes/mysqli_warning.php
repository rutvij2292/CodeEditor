<?php

/**
 * Represents one or more MySQL warnings.
 */
final class mysqli_warning
{
    /**
     * @var string
     */
    public string $message;

    /**
     * @var string
     */
    public string $sqlstate;

    /**
     * @var int
     */
    public int $errno;

    /**
     * The __construct purpose
     */
    private function __construct() {}

    /**
     * Move to the next warning
     * @return bool True if it successfully moved to the next warning
     */
    public function next(): bool {}
}
