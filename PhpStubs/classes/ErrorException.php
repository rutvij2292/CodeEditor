<?php

/**
 * An Error Exception.
 */
class ErrorException extends Exception
{
    protected int $severity;

    /**
     * Constructs the exception
     * @param string $message [optional] The Exception message to throw.
     * @param int $code [optional] The Exception code.
     * @param int $severity [optional] The severity level of the exception.
     * @param string $filename [optional] The filename where the exception is thrown.
     * @param int $line [optional] The line number where the exception is thrown.
     * @param Throwable $previous [optional] The previous exception used for the exception chaining.
     */
    public function __construct(
        string $message = "",
        int $code = 0,
        int $severity = 1,
        string|null $filename = null,
        int|null $line = null,
        Throwable|null $previous = null
    ) {}

    /**
     * Gets the exception severity
     * @return int the severity level of the exception.
     */
    final public function getSeverity(): int {}
}
