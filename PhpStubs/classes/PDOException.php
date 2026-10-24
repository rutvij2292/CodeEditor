<?php

/**
 * Represents an error raised by PDO. You should not throw a
 * PDOException from your own code.
 */
class PDOException extends RuntimeException
{
    public array|null $errorInfo;

    protected $code;
}
