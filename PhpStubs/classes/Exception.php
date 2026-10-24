<?php

/**
 * Exception is the base class for
 * all Exceptions.
 */
class Exception implements Throwable
{
    /**
     * The error message
     * @var string
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
     * Cached string representation of the exception (used by __toString)
     */
    private string $string = '';

    /**
     * Internal storage for the exception stack trace
     */
    private array $trace = [];

    /**
     * The previous throwable used for exception chaining
     */
    private ?Throwable $previous = null;

    /**
     * Clone the exception
     * Tries to clone the Exception, which results in Fatal error.
     * @return void No value is returned.
     */
    private function __clone(): void {}

    /**
     * Construct the exception. Note: The message is NOT binary safe.
     * @param string $message [optional] The Exception message to throw.
     * @param int $code [optional] The Exception code.
     * @param null|Throwable $previous [optional] The previous throwable used for the exception chaining.
     */
    public function __construct(
        string $message = "",
        int $code = 0,
        Throwable|null $previous = null
    ) {}

    /**
     * Gets the Exception message
     * @return string the Exception message as a string.
     */
    final public function getMessage(): string {}

    /**
     * Gets the Exception code
     * @return mixed|int the exception code as integer in Exception but possibly as other type in Exception descendants (for example as string in PDOException).
     */
    final public function getCode() {}

    /**
     * Gets the file in which the exception occurred
     * @return string the filename in which the exception was created.
     */
    final public function getFile(): string {}

    /**
     * Gets the line in which the exception occurred
     * @return int the line number where the exception was created.
     */
    final public function getLine(): int {}

    /**
     * Gets the stack trace
     * @return array the Exception stack trace as an array.
     */
    final public function getTrace(): array {}

    /**
     * Returns previous Exception
     * @return null|Throwable Returns the previous Throwable if available, or NULL otherwise. or null otherwise.
     */
    final public function getPrevious(): ?Throwable {}

    /**
     * Gets the stack trace as a string
     * @return string the Exception stack trace as a string.
     */
    final public function getTraceAsString(): string {}

    /**
     * String representation of the exception
     * @return string the string representation of the exception.
     */
    public function __toString(): string {}

    public function __wakeup(): void {}
}
