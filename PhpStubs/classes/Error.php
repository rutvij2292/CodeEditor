<?php

/**
 * Error is the base class for all internal PHP error exceptions.
 * @since 7.0
 */
class Error implements Throwable
{
    /**
     * The error message
     */
    protected $message;

    /**
     * The error code
     */
    protected $code;

    /**
     * The filename where the error happened
     */
    protected string $file;

    /**
     * The line where the error happened
     */
    protected int $line;

    /**
     * Cached string representation of the error (used by __toString)
     */
    private string $string = '';

    /**
     * Internal storage for the error stack trace
     */
    private array $trace = [];

    /**
     * The previous throwable used for error chaining
     */
    private ?Throwable $previous = null;

    /**
     * Construct the error object.
     * @param string $message [optional] The Error message to throw.
     * @param int $code [optional] The Error code.
     * @param null|Throwable $previous [optional] The previous throwable used for the exception chaining.
     */
    public function __construct(
        string $message = "",
        int $code = 0,
        Throwable|null $previous = null
    ) {}

    /**
     * Gets the message
     * @return string Returns the error message as a string.
     * @since 7.0
     */
    final public function getMessage(): string {}

    /**
     * Gets the exception code
     * @return int Returns the exception code as integer in Exception but possibly as other type in Exception descendants (for example as string in PDOException).
     * @since 7.0
     */
    final public function getCode() {}

    /**
     * Gets the file in which the exception occurred
     * @return string Returns the name of the file from which the object was thrown.
     * @since 7.0
     */
    final public function getFile(): string {}

    /**
     * Gets the line on which the object was instantiated
     * @return int Returns the line number where the thrown object was instantiated.
     * @since 7.0
     */
    final public function getLine(): int {}

    /**
     * Gets the stack trace
     * @return array Returns the stack trace as an array in the same format as debug_backtrace().
     * @since 7.0
     */
    final public function getTrace(): array {}

    /**
     * Gets the stack trace as a string
     * @return string Returns the stack trace as a string.
     * @since 7.0
     */
    final public function getTraceAsString(): string {}

    /**
     * Returns the previous Throwable
     * @return null|Throwable Returns the previous Throwable if available, or NULL otherwise.
     * @since 7.0
     */
    final public function getPrevious(): ?Throwable {}

    /**
     * Gets a string representation of the thrown object
     * @return string Returns the string representation of the thrown object.
     * @since 7.0
     */
    public function __toString(): string {}

    /**
     * Clone the error
     * Error can not be clone, so this method results in fatal error.
     * @return void No value is returned.
     */
    private function __clone(): void {}

    public function __wakeup(): void {}
}
