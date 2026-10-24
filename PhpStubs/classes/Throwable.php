<?php

/**
 * Throwable is the base interface for any object that can be thrown via a throw statement in PHP 7,
 * including Error and Exception.
 * @since 7.0
 */
interface Throwable extends Stringable
{
    /**
     * Gets the message
     * @return string Returns the message associated with the thrown object.
     * @since 7.0
     */
    public function getMessage(): string;

    /**
     * Gets the exception code
     * @return int Returns the exception code as integer in Exception but possibly as other type in Exception descendants (for example as string in PDOException).
     * @since 7.0
     */
    public function getCode();

    /**
     * Gets the file in which the exception occurred
     * @return string Returns the name of the file from which the object was thrown.
     * @since 7.0
     */
    public function getFile(): string;

    /**
     * Gets the line on which the object was instantiated
     * @return int Returns the line number where the thrown object was instantiated.
     * @since 7.0
     */
    public function getLine(): int;

    /**
     * Gets the stack trace
     * @return array Returns the stack trace as an array in the same format as debug_backtrace().
     * @since 7.0
     */
    public function getTrace(): array;

    /**
     * Gets the stack trace as a string
     * @return string Returns the stack trace as a string.
     * @since 7.0
     */
    public function getTraceAsString(): string;

    /**
     * Returns the previous Throwable
     * @return null|Throwable Returns the previous Throwable if available, or NULL otherwise.
     * @since 7.0
     */
    public function getPrevious(): Throwable|null;

    /**
     * Gets a string representation of the thrown object
     * @return string Returns the string representation of the thrown object.
     * @since 7.0
     */
    public function __toString(): string;
}
